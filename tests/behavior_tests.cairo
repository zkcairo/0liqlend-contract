// Test the standard workflow: make an offer, have it accepted, and so
// During each of these steps, make a lot of assert to make sure everything works good

use starknet::ContractAddress;

#[cfg(test)]
pub mod behavior_tests {
    // From the contract
    use mycode::{ IMyCodeDispatcher, IMyCodeDispatcherTrait };
    use mycode::{ IMyCodeSafeDispatcher, IMyCodeSafeDispatcherTrait };
    use mycode::mock_erc20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    use mycode::datastructures::{ LendingOffer, BorrowingOffer, Price, Match, Collateral };
    use mycode::constants;
    use mycode::utilities::{ interest_to_repay, assert_offer_can_be_repay };
    use mycode::utilities::{ scale_to_18_decimals, inverse_scale_to_18_decimals };
    // Forge and starknet imports
    use snforge_std::{ declare, ContractClassTrait, BlockId, CheatSpan, start_cheat_caller_address, cheat_caller_address, start_cheat_block_timestamp_global };
    use starknet::{ContractAddress, contract_address_const, get_block_timestamp };

    fn deploy_mycode() -> (IMyCodeDispatcher, ContractAddress) {
        let contract = declare("MyCode").unwrap();
        let mut constructor_calldata = array![];
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        let dispatcher = IMyCodeDispatcher { contract_address };
        (dispatcher, contract_address)
    }
    // With safe dispatcher
    fn deploy_safe_mycode() -> (IMyCodeSafeDispatcher, ContractAddress) {
        let contract = declare("MyCode").unwrap();
        let mut constructor_calldata = array![];
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        let dispatcher = IMyCodeSafeDispatcher { contract_address };
        (dispatcher, contract_address)
    }

    fn deploy_erc20(n: u256, dec1: felt252, dec2: felt252) -> Span<(IERC20Dispatcher, ContractAddress)> {
        let contract = declare("mock_erc20").unwrap();
        if n == 1 {
            let mut constructor_calldata = array![dec1];
            let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
            let dispatcher = IERC20Dispatcher { contract_address };
            array![(dispatcher, contract_address)].span()
        } else {
            let mut constructor_calldata = array![dec1];
            let (contract_address_1, _) = contract.deploy(@constructor_calldata).unwrap();
            let dispatcher_1 = IERC20Dispatcher { contract_address: contract_address_1 };
            let mut constructor_calldata = array![dec2];
            let (contract_address_2, _) = contract.deploy(@constructor_calldata).unwrap();
            let dispatcher_2 = IERC20Dispatcher { contract_address: contract_address_2 };
            array![(dispatcher_1, contract_address_1), (dispatcher_2, contract_address_2)].span()
        }
    }

    // A basic price, that respect the condition of mycode::utilities::assert_validity_of_price
    fn create_basic_price() -> Price {
        Price {
            rate: constants::APR_1_PERCENT,
            minimal_duration: constants::SECONDS_PER_HOUR,
            maximal_duration: constants::SECONDS_PER_HOUR + constants::SECONDS_PER_DAY
        }
    }

    #[test]
    fn test_make_and_disable_lending_offer() {
        // Contract
        let (contract, contract_address) = deploy_mycode();
        let user = contract_address_const::<1>();
        start_cheat_caller_address(contract_address, user);
        // Erc20
        let (erc20, erc20_address) = *deploy_erc20(1, 18, 18)[0];
        erc20.mint(user, 100);
        cheat_caller_address(erc20_address, user, CheatSpan::TargetCalls(1));
        erc20.approve(contract_address, 100);
        assert_eq!(erc20.allowance(user, contract_address), 100);

        // Make the lending offer
        let token = erc20_address;
        let amount = 100;
        let accepted_collateral = 50; // Todo c'est sensé être la categorie, pas autre chose
        let price = create_basic_price();
        contract.make_lending_offer(token, amount, accepted_collateral, price);
        
        // Assert some stuff
        let lending_offer = contract.all_lending_offers_at(0);
        assert_eq!(lending_offer.is_active, true);
        assert_eq!(lending_offer.token, token);
        assert_eq!(lending_offer.total_amount, amount); // TODO: only correct because we have 18 decimals - todo
        assert_eq!(lending_offer.amount_available, amount);
        assert_eq!(lending_offer.price, price);
        assert_eq!(lending_offer.accepted_collateral, accepted_collateral);

        // Withdraw the offer
        contract.disable_lending_offer(0);
        let withdrawn_lending_offer = contract.all_lending_offers_at(0);
        assert_eq!(withdrawn_lending_offer.is_active, false);
    }

    #[test]
    fn test_make_and_disable_borrowing_offer() {
        // Contract
        let (contract, contract_address) = deploy_mycode();
        let user = contract_address_const::<1>();
        start_cheat_caller_address(contract_address, user);
        // Erc20
        let (erc20, erc20_address) = *deploy_erc20(1, 18, 18)[0];
        erc20.mint(user, 100);
        cheat_caller_address(erc20_address, user, CheatSpan::TargetCalls(1));
        erc20.approve(contract_address, 100);
        assert_eq!(erc20.allowance(user, contract_address), 100);

        // Make the borrowing offer
        let token_lend = erc20_address;
        let amount_lend = 100;
        let price = create_basic_price();
        let token_collateral = erc20_address;
        let amount_collateral = 50;
        contract.make_borrowing_offer_allowance(amount_lend, price, token_collateral, amount_collateral);
        
        // Asserts some stuff
        let borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(borrowing_offer.is_active, true);
        assert_eq!(borrowing_offer.proposer, user);
        assert_eq!(borrowing_offer.total_amount, amount_lend);
        assert_eq!(borrowing_offer.amount_available, amount_lend);
        assert_eq!(borrowing_offer.price, price);
        assert_eq!(borrowing_offer.is_allowance, true);
        assert_eq!(borrowing_offer.token_collateral, token_collateral);
        assert_eq!(borrowing_offer.amount_collateral, amount_collateral);

        // Withdraw the offer
        contract.disable_borrowing_offer(0);
        let disabled_borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(disabled_borrowing_offer.is_active, false);
    }

    #[test]
    fn test_make_transform_and_disable_borrowing_offer_deposit() {
        // Contract
        let (contract, contract_address) = deploy_mycode();
        let user = contract_address_const::<1>();
        start_cheat_caller_address(contract_address, user);
        // Erc20
        let (erc20, erc20_address) = *deploy_erc20(1, 18, 18)[0];
        erc20.mint(user, 100);
        cheat_caller_address(erc20_address, user, CheatSpan::TargetCalls(1));
        erc20.approve(contract_address, 100);
        assert_eq!(erc20.allowance(user, contract_address), 100);

        // Make the borrowing offer
        let token_lend = erc20_address;
        let amount_lend = 100;
        let price = create_basic_price();
        let token_collateral = erc20_address;
        let amount_collateral = 50;
        contract.make_borrowing_offer_allowance(amount_lend, price, token_collateral, amount_collateral);
        
        // Asserts some stuff
        let borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(borrowing_offer.is_active, true);
        assert_eq!(borrowing_offer.proposer, user);
        assert_eq!(borrowing_offer.total_amount, amount_lend);
        assert_eq!(borrowing_offer.amount_available, amount_lend);
        assert_eq!(borrowing_offer.price, price);
        assert_eq!(borrowing_offer.is_allowance, true);
        assert_eq!(borrowing_offer.token_collateral, token_collateral);
        assert_eq!(borrowing_offer.amount_collateral, amount_collateral);

        // Transform it into a deposit offer
        let len_collateral_before = contract.all_collateral_user_len(user);
        assert_eq!(len_collateral_before, 0);
        contract.from_borrowing_allowance_offer_to_borrowing_deposit_offer(0);
        let new_borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(new_borrowing_offer.is_allowance, false);
        let len_collateral_after = contract.all_collateral_user_len(user);
        assert_eq!(len_collateral_after, len_collateral_before + 1);
        assert_eq!(contract.all_collateral_user_at(user, 0).owner, user); // Verify we have a collateral

        // Disable it
        contract.disable_borrowing_offer(0);
        let disabled_borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(disabled_borrowing_offer.is_active, false);
    }

    #[test]
    fn test_make_transform_and_withdraw_borrowing_offer_deposit() {
        // Contract
        let (contract, contract_address) = deploy_mycode();
        let user = contract_address_const::<1>();
        start_cheat_caller_address(contract_address, user);
        // Erc20
        let (erc20, erc20_address) = *deploy_erc20(1, 18, 18)[0];
        erc20.mint(user, 100);
        cheat_caller_address(erc20_address, user, CheatSpan::TargetCalls(1));
        erc20.approve(contract_address, 100);
        assert_eq!(erc20.allowance(user, contract_address), 100);

        // Make the borrowing offer
        let token_lend = erc20_address;
        let amount_lend = 100;
        let price = create_basic_price();
        let token_collateral = erc20_address;
        let amount_collateral = 50;
        contract.make_borrowing_offer_allowance(amount_lend, price, token_collateral, amount_collateral);
        
        // Asserts some stuff
        let borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(borrowing_offer.is_active, true);
        assert_eq!(borrowing_offer.proposer, user);
        assert_eq!(borrowing_offer.total_amount, amount_lend);
        assert_eq!(borrowing_offer.amount_available, amount_lend);
        assert_eq!(borrowing_offer.price, price);
        assert_eq!(borrowing_offer.is_allowance, true);
        assert_eq!(borrowing_offer.token_collateral, token_collateral);
        assert_eq!(borrowing_offer.amount_collateral, amount_collateral);

        // Transform it into a deposit offer
        let len_collateral_before = contract.all_collateral_user_len(user);
        assert_eq!(len_collateral_before, 0);
        contract.from_borrowing_allowance_offer_to_borrowing_deposit_offer(0);
        let new_borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(new_borrowing_offer.is_allowance, false);
        let len_collateral_after = contract.all_collateral_user_len(user);
        assert_eq!(len_collateral_after, len_collateral_before + 1);
        assert_eq!(contract.all_collateral_user_at(user, 0).owner, user); // Verify we have a collateral

        // Withdraw the offer
        contract.withdraw_collateral(0);
        contract.disable_borrowing_offer(0);
        let disabled_borrowing_offer = contract.all_borrowing_offers_at(0);
        assert_eq!(disabled_borrowing_offer.is_active, false);
    }

    // Todo, tester le match qui fait si les apr sont pas good
    // Todo make the test fuzz with the amount and so
    // Ok
    // fn test_match_offer(_decimals1: u256, _decimals2: u256) {
    // match contract.repay_debt(0) {
    //     Result::Ok(_) => (),
    //     Result::Err(panic_data) => {
    //        panic(panic_data);
    //     }
    // }
    #[test]
    fn test_match_offer() {
        let _decimals1: u256 = 5;
        let _decimals2: u256 = 6;
    // fn test_match_offer(_decimals1: u256, _decimals2: u256) {
        let _loan_duration = 34567898765;

        let min_duration_date = constants::SECONDS_PER_DAY;
        let max_duration_date = constants::MIN_TIME_SPACING_FOR_OFFERS + constants::SECONDS_PER_YEAR;
        let loan_duration = min_duration_date + _loan_duration % (max_duration_date - min_duration_date);

        let decimals1: felt252 = (1 + _decimals1 % 17).try_into().unwrap();
        let decimals2: felt252 = (1 + _decimals2 % 17).try_into().unwrap();
        let (contract, contract_address) = deploy_safe_mycode();
        let arr = deploy_erc20(2, decimals1.into(), decimals2.into());
        let (erc20_lender, erc20_address_lender) = *arr[0];
        let (erc20_borrower, erc20_address_borrower) = *arr[1];
        let lender = contract_address_const::<1>();
        let borrower = contract_address_const::<2>();
        let amount_lend = scale_to_18_decimals(erc20_address_lender, 1000000000000000000);
        let amount_borrow = scale_to_18_decimals(erc20_address_borrower, 2000000000000000000);
        let amount_repay = scale_to_18_decimals(erc20_address_lender, 3000000000000000000);
        erc20_lender.mint(lender, amount_lend);
        erc20_borrower.mint(borrower, amount_borrow);
        erc20_lender.mint(borrower, amount_repay); // To repay the debt

        // Set price and ltv for the collateral
        cheat_caller_address(contract_address, constants::ADMIN_ADDRESS.try_into().unwrap(), CheatSpan::TargetCalls(2));
        contract.set_price(erc20_address_borrower, 1000000000000000000).unwrap(); // value: 10**18
        contract.set_ltv(erc20_address_borrower, constants::LTV_100_PERCENT).unwrap();
        
        // ERC20 approves
        cheat_caller_address(erc20_address_lender, lender, CheatSpan::TargetCalls(1));
        erc20_lender.approve(contract_address, amount_lend);
        cheat_caller_address(erc20_address_borrower, borrower, CheatSpan::TargetCalls(1));
        erc20_borrower.approve(contract_address, amount_borrow);
        cheat_caller_address(erc20_address_lender, borrower, CheatSpan::TargetCalls(1));
        erc20_lender.approve(contract_address, amount_repay);
        
        // Create the lending offer
        println!("Create lending offer");
        let lending_token = erc20_address_lender;
        let lending_amount = amount_lend;
        let lending_price = Price { rate: 10 * constants::APR_1_PERCENT, minimal_duration: min_duration_date , maximal_duration: max_duration_date };
        start_cheat_caller_address(contract_address, lender);
        contract.make_lending_offer(lending_token, lending_amount, 0, lending_price).unwrap();
        let lending_offer = contract.all_lending_offers_at(0).unwrap();
        assert_eq!(lending_offer.is_active, true);
        assert_eq!(lending_offer.token, lending_token);
        assert_eq!(lending_offer.total_amount, lending_amount);
        assert_eq!(lending_offer.amount_available, lending_amount);
        assert_eq!(lending_offer.price, lending_price);

        // Create the borrowing offer
        println!("Create borrowing offer");
        let borrowing_amount = amount_borrow;
        let borrowing_price = Price { rate: 11 * constants::APR_1_PERCENT, minimal_duration: min_duration_date , maximal_duration: max_duration_date };
        let borrowing_collateral = erc20_address_borrower;
        let borrowing_collateral_amount = amount_borrow;
        start_cheat_caller_address(contract_address, borrower);
        contract.make_borrowing_offer_allowance(borrowing_amount, borrowing_price, borrowing_collateral, borrowing_collateral_amount).unwrap();
        let borrowing_offer = contract.all_borrowing_offers_at(0).unwrap();
        assert_eq!(borrowing_offer.is_active, true);
        assert_eq!(borrowing_offer.proposer, borrower);
        assert_eq!(borrowing_offer.total_amount, borrowing_amount);
        assert_eq!(borrowing_offer.amount_available, borrowing_amount);
        assert_eq!(borrowing_offer.price, borrowing_price);
        assert_eq!(borrowing_offer.is_allowance, true);
        assert_eq!(borrowing_offer.token_collateral, borrowing_collateral);
        assert_eq!(borrowing_offer.amount_collateral, borrowing_collateral_amount);

        // Todo assert that we can't do a match if the offer are inactive
        // Todo assert each part of this flow

        // Make a match, and assert stuff
        println!("Make a match");
        let match_amount = 1000000000000000000; // 10**18 : a loan of 1$
        start_cheat_caller_address(contract_address, borrower);
        contract.match_offer(0, 0, match_amount).unwrap();
        // match contract.match_offer(0, 0, match_amount) {
        //     Result::Ok(_) => panic!("Entrypoint did not panic"),
        //     Result::Err(panic_data) => {
        //         assert(*panic_data.at(0) == 'PANIC', *panic_data.at(0));
        //         assert(*panic_data.at(1) == 'DAYTAH', *panic_data.at(1));
        //     }
        // };

        let matched_lending_offer = contract.all_lending_offers_at(0).unwrap();
        let matched_borrowing_offer = contract.all_borrowing_offers_at(0).unwrap();
        let current_match = contract.all_current_match_at(0).unwrap();
        assert_eq!(matched_lending_offer.is_active, true);
        assert_eq!(matched_borrowing_offer.is_active, true);
        assert_eq!(current_match.is_active, true);
        assert_eq!(current_match.lending_offer_id, 0);
        assert_eq!(current_match.borrowing_offer_id, 0);
        assert_eq!(current_match.amount, match_amount);
        assert_eq!(matched_lending_offer.amount_available, lending_amount - match_amount);
        assert_eq!(matched_lending_offer.total_amount, lending_amount);
        assert_eq!(matched_borrowing_offer.amount_available, borrowing_amount - match_amount);
        assert_eq!(erc20_lender.balanceOf(lender), amount_lend - inverse_scale_to_18_decimals(erc20_address_lender, match_amount));
        assert_eq!(erc20_lender.balanceOf(borrower), amount_repay + inverse_scale_to_18_decimals(erc20_address_lender, match_amount));

        let current_time = get_block_timestamp();
        println!("Try to repay debt too early/late");

        // Try to advance time by not enough and fail
        start_cheat_block_timestamp_global(current_time + min_duration_date - 1);
        let result = contract.repay_debt(0);
        assert_eq!(result.is_err(), true);

        // Try to advance time by too much and fail
        start_cheat_block_timestamp_global(current_time + max_duration_date + 1);
        let result = contract.repay_debt(0);
        assert_eq!(result.is_err(), true);

        // Advance time by the good duration and repay
        start_cheat_block_timestamp_global(current_time + loan_duration);
        println!("Repay debt before");
        contract.repay_debt(0).unwrap();
        println!("Repay debt after");

        // Todo asserts and so
        let lending_offer_after_repay = contract.all_lending_offers_at(0).unwrap();
        let borrowing_offer_after_repay = contract.all_borrowing_offers_at(0).unwrap();
        let current_match_after_repay = contract.all_current_match_at(0).unwrap();
        assert_eq!(lending_offer_after_repay.is_active, true);
        assert_eq!(borrowing_offer_after_repay.is_active, true);
        assert_eq!(current_match_after_repay.is_active, false);

        // Computation of interest to pay
        let (interest_lender, fee) = interest_to_repay(current_match, get_block_timestamp());
        println!("Interest for lender {}, the fee {}, match_amount {}", interest_lender, fee, match_amount);
        println!("scaled interest {}", inverse_scale_to_18_decimals(erc20_address_lender, interest_lender));
        //assert_eq!(interest_lender, match_amount * 10 / 100);
        //assert_eq!(fee, match_amount * 1 / 100);
        assert_ge!(erc20_lender.balanceOf(lender), amount_lend + inverse_scale_to_18_decimals(erc20_address_lender, interest_lender));
        assert_eq!(erc20_lender.balanceOf(borrower), amount_repay - inverse_scale_to_18_decimals(erc20_address_lender, interest_lender) - inverse_scale_to_18_decimals(erc20_address_lender, fee));
        assert_eq!(erc20_lender.balanceOf(contract_address), inverse_scale_to_18_decimals(erc20_address_lender, fee));

        // Todo make sure we can reborrow and relend
        assert_eq!(lending_offer_after_repay.amount_available, lending_offer.amount_available + interest_lender);
        assert_eq!(borrowing_offer_after_repay.amount_available, borrowing_offer.amount_available);
    }
}
