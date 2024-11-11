// Todo remplacer ERC20 dispatcher par un custom "transferdispatcher"

// Todo: https://github.com/gaetbout/starknet-mutation-testing

// Todo ajouter un test pour quand le frais pris est superieur a 1%

// Todo recompute value of collateral

// Todo quand une borrowing offer allowance est taken, la split en deux entre une collateral et une allowance
// afin de ne pas prendre toute l'allowance dans le collateral

pub mod utilities;
pub mod integration;
pub mod datastructures;
pub mod constants;
pub mod mock_erc20;

use datastructures::{LendingOffer, BorrowingOffer, Price, Match, Collateral};
use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
pub trait IMyCode<TContractState> {
    // The actual code
    fn make_lending_offer(ref self: TContractState, token: ContractAddress, amount: u256, accepted_collateral: u256, price: Price);
    fn disable_lending_offer(ref self: TContractState, offer_id: u64);
    fn make_borrowing_offer_allowance(ref self: TContractState, amount: u256, price: Price, token_collateral: ContractAddress, amount_collateral: u256);
    fn make_borrowing_offer_deposit(ref self: TContractState, amount: u256, price: Price, collateral_id: u64);
    fn disable_borrowing_offer(ref self: TContractState, offer_id: u64);
    fn withdraw_collateral(ref self: TContractState, collateral_id: u64);
    fn from_borrowing_allowance_offer_to_borrowing_deposit_offer(ref self: TContractState, offer_id: u64);
    fn match_offer(ref self: TContractState, lending_offer_id: u64, borrowing_offer_id: u64, amount: u256);
    fn repay_debt(ref self: TContractState, match_offer_id: u64);
    fn liquidate(ref self: TContractState, match_offer_id: u64);
    fn set_price(ref self: TContractState, address: ContractAddress, price: u256);
    fn set_ltv(ref self: TContractState, address: ContractAddress, ltv: u256);
    fn upgrade(ref self: TContractState, new_class_hash: ClassHash);

    // Getters - frontend and helpers
    // Helper
    fn frontend_actual_lending_amount(self: @TContractState, offer_id: u64) -> u256;
    fn frontend_actual_borrowing_amount(self: @TContractState, offer_id: u64) -> u256;
    // UX
    fn frontend_get_all_offers(self: @TContractState, category: felt252) -> (Span<BorrowingOffer>, Span<LendingOffer>);
    // Frontpage
    fn frontend_best_available_yield(self: @TContractState, category: felt252) -> (u256, u256);
    fn frontend_available_to_lend_and_borrow(self: @TContractState, category: felt252) -> (u256, u256);
    fn frontend_get_all_lending_offers_of_user(self: @TContractState, category: felt252, user: ContractAddress) -> Span<LendingOffer>;
    fn frontend_get_all_borrowing_offers_of_user(self: @TContractState, category: felt252, user: ContractAddress) -> Span<BorrowingOffer>;
    fn frontend_get_all_matches_of_user(self: @TContractState, category: felt252, user: ContractAddress) -> (Span<(Match, ContractAddress)>, Span<(Match, ContractAddress)>);
    fn frontend_get_all_collaterals_of_user(self: @TContractState, category: felt252, user: ContractAddress) -> Span<Collateral>;

    // Getters functions to test the contract - maybe to remove when deploying
    fn all_lending_offers_at(self: @TContractState, idx: u64) -> LendingOffer;
    fn all_lending_offers_len(self: @TContractState) -> u64;
    fn all_borrowing_offers_at(self: @TContractState, idx: u64) -> BorrowingOffer;
    fn all_borrowing_offers_len(self: @TContractState) -> u64;
    fn all_current_match_at(self: @TContractState, idx: u64) -> Match;
    fn all_current_match_len(self: @TContractState) -> u64;
    fn all_collateral_user_at(self: @TContractState, user: ContractAddress, idx: u64) -> Collateral;
    fn all_collateral_user_len(self: @TContractState, user: ContractAddress) -> u64;
    fn get_price(self: @TContractState, address: ContractAddress) -> u256;
    fn get_ltv(self: @TContractState, address: ContractAddress) -> u256;

    // Debug
    fn withdraw(ref self: TContractState, token: ContractAddress);

    // Points
    fn frontend_get_user_points(self: @TContractState, user: ContractAddress) -> u256;
    fn frontend_get_total_points(self: @TContractState) -> u256;
    fn set_points_multiplier(ref self: TContractState, multiplier: u256);
}

#[starknet::contract]
pub mod MyCode {
    use super::IMyCode;
    use super::constants;
    use super::mock_erc20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    // Our structures
    use mycode::datastructures::{ LendingOffer, BorrowingOffer, Price, Match, Collateral };
    // Utilities
    use mycode::utilities::{ assert_is_admin, assert_is_lending_asset, assert_offer_can_be_repay, assert_validity_of_price };
    use mycode::utilities::{ interest_to_repay, max_to_repay, max2, min2, min2_256, min3, scale_to_18_decimals, inverse_scale_to_18_decimals };
    use mycode::integration::{ aux_compute_value_of_asset, category_id_from_address, liquidate_collateral };
    use mycode::constants::{ STRK_CATEGORY };
    // Starknet
    use starknet::{ ContractAddress, ClassHash };
    use starknet::storage::{ Vec, VecTrait, MutableVecTrait };
    use starknet::storage::{ Map, StoragePathEntry, StorageMapReadAccess, StorageMapWriteAccess };
    use starknet::{ syscalls::replace_class_syscall, get_caller_address, get_contract_address, contract_address_const, get_block_timestamp };

    #[storage]
    struct Storage {
        all_lending_offers: Vec<LendingOffer>,
        all_borrowing_offers: Vec<BorrowingOffer>,
        all_current_match: Vec<Match>,
        all_collateral_user: Map<ContractAddress, Vec<Collateral>>,

        price_information: Map<ContractAddress, u256>,  // Price of assets - see integration.cairo for more info
        ltv_information: Map<ContractAddress, u256>,    // Loan To Value info about assets - see integration.cairo
        
        // For the function from_borrowing_allowance_offer_to_borrowing_deposit_offer -- see the code
        me: bool,

        // Points
        points_multiplier: u256,
        total_points: u256,
        user_points: Map<ContractAddress, u256>,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {}

    fn compute_value_of_asset(self: @ContractState, amount: u256, address: ContractAddress) -> u256 {
        let erc20 = IERC20Dispatcher { contract_address: address };
        let price = self.price_information.read(address);
        let ltv = self.ltv_information.read(address);
        aux_compute_value_of_asset(amount, erc20, price, ltv)
    }

    #[abi(embed_v0)]
    impl MyCodeImpl of super::IMyCode<ContractState> {

        fn withdraw(ref self: ContractState, token: ContractAddress) {
            assert_is_admin();
            let erc20 = IERC20Dispatcher { contract_address: token };
            erc20.transfer(get_caller_address(), erc20.balanceOf(get_contract_address()));
        }

        // Getters functions - all read only - only used in the tests, never in the contract code
        // I reserve the right to change these getters, including
        // but not only return wrong values, delete them, change their arguments etc... - use them at risk
        fn all_lending_offers_at(self: @ContractState, idx: u64) -> LendingOffer { self.all_lending_offers.at(idx).read() }
        fn all_lending_offers_len(self: @ContractState) -> u64 { self.all_lending_offers.len() }
        fn all_borrowing_offers_at(self: @ContractState, idx: u64) -> BorrowingOffer { self.all_borrowing_offers.at(idx).read() }
        fn all_borrowing_offers_len(self: @ContractState) -> u64 { self.all_borrowing_offers.len() }
        fn all_current_match_at(self: @ContractState, idx: u64) -> Match { self.all_current_match.at(idx).read() }
        fn all_current_match_len(self: @ContractState) -> u64 { self.all_current_match.len() }
        fn all_collateral_user_at(self: @ContractState, user: ContractAddress, idx: u64) -> Collateral { self.all_collateral_user.entry(user).at(idx).read() }
        fn all_collateral_user_len(self: @ContractState, user: ContractAddress) -> u64 { self.all_collateral_user.entry(user).len() }
        fn get_price(self: @ContractState, address: ContractAddress) -> u256 { self.price_information.read(address) }
        fn get_ltv(self: @ContractState, address: ContractAddress) -> u256 { self.ltv_information.read(address) }
        
        // The real code of the contract start here
        // @dev: amount is in 10**18 scale
        fn make_lending_offer(ref self: ContractState, token: ContractAddress, amount: u256, accepted_collateral: u256, price: Price) {
            assert_validity_of_price(price);
            assert_is_lending_asset(token);

            let proposer = get_caller_address();
            
            let lending_offer = LendingOffer {
                id: self.all_lending_offers.len(),
                is_active: true,
                proposer,
                token,
                total_amount: amount,
                amount_available: amount,
                price,
                accepted_collateral,
            };

            self.all_lending_offers.append().write(lending_offer);
        }
        fn disable_lending_offer(ref self: ContractState, offer_id: u64) {
            let mut lending_offer: LendingOffer = self.all_lending_offers.at(offer_id).read();
            assert!(get_caller_address() == lending_offer.proposer, "Only the proposer can disable the offer");
            assert!(lending_offer.is_active, "The lending offer is not active");
            lending_offer.is_active = false;
            self.all_lending_offers.at(offer_id).write(lending_offer);
        }
        // @dev: amount is in 10**18 scale
        fn make_borrowing_offer_allowance(ref self: ContractState, amount: u256, price: Price, token_collateral: ContractAddress, amount_collateral: u256) {
            assert_validity_of_price(price);
            let proposer = get_caller_address();
            let borrowing_offer = BorrowingOffer {
                id: self.all_borrowing_offers.len(),
                is_active: true,
                proposer,
                total_amount: amount,
                amount_available: amount,
                price,
                is_allowance: true,
                token_collateral,
                amount_collateral,
                collateral_id: 99999999999999, // Todo mettre une valeur absurde
            };
            self.all_borrowing_offers.append().write(borrowing_offer);
        }
        // Transform a borrowing offer from allowance to deposit - used when matching
        fn from_borrowing_allowance_offer_to_borrowing_deposit_offer(ref self: ContractState, offer_id: u64) {
            let mut borrowing_offer = self.all_borrowing_offers.at(offer_id).read();
            assert!(
                (get_caller_address() == borrowing_offer.proposer) ||
                (self.me.read()), // Check if the function is called from the function make_borrowing_offer_allowance
                "Only the proposer and the contract can transform the offer");
            assert!(borrowing_offer.is_active, "The borrowing offer is not active");
            assert!(borrowing_offer.is_allowance, "The borrowing offer is not an allowance offer");

            // Convert the borrowing offer from allowance to deposit
            borrowing_offer.is_allowance = false;
            
            // Deposit the collateral into the contract
            let token = borrowing_offer.token_collateral;
            let amount = borrowing_offer.amount_collateral;
            let erc20 = IERC20Dispatcher { contract_address: token };
            erc20.transferFrom(borrowing_offer.proposer, get_contract_address(), amount);

            // Inscribe the collateral in memory
            // Note that during all the time the collateral is held in the platform it cannot change its value
            // - even if the collateral increased in value
            // - this is not the excepted behavior, but borrowers that are aware of that can withdraw and re-deposit
            // - their collateral to have recomputed the value of their collateral.
            // - (which sadly cannot be done when you have a loan atm with this collateral)
            let value_collateral = compute_value_of_asset(@self, amount, token);
            let collateral = Collateral {
                id: self.all_collateral_user.entry(borrowing_offer.proposer).len(),
                is_active: true,
                owner: borrowing_offer.proposer,
                token: token,
                category: category_id_from_address(token),
                deposited_amount: amount,
                total_value: value_collateral,
                available_value: value_collateral,
            };
            borrowing_offer.collateral_id = self.all_collateral_user.entry(borrowing_offer.proposer).len();
            self.all_collateral_user.entry(borrowing_offer.proposer).append().write(collateral);

            // Update the offer in memory
            self.all_borrowing_offers.at(offer_id).write(borrowing_offer);
        }
        // This function do NOT check that the collateral exist
        // If you call this function yourself, with for instance 0 collaterals deposited and call it with 0
        // It WILL succeed, and once you deposit a collateral this offer will become live instantly
        // This is the wanted behavior - if users choose to call this function with a collateal that doesn't exist yet they need to be careful
        fn make_borrowing_offer_deposit(ref self: ContractState, amount: u256, price: Price, collateral_id: u64) {
            assert_validity_of_price(price);
            // Collateral_id is in the array all_collateral_user(get_caller_address)
            // So, the owner is obviously the caller, and we do not check that
            let borrowing_offer = BorrowingOffer {
                id: self.all_borrowing_offers.len(),
                is_active: true,
                proposer: get_caller_address(),
                total_amount: amount,
                amount_available: amount,
                price,
                is_allowance: false,
                token_collateral: contract_address_const::<0>(),
                amount_collateral: 0,
                collateral_id
            };
            self.all_borrowing_offers.append().write(borrowing_offer);
        }
        fn disable_borrowing_offer(ref self: ContractState, offer_id: u64) {
            let mut borrowing_offer = self.all_borrowing_offers.at(offer_id).read();
            assert!(get_caller_address() == borrowing_offer.proposer, "Only the proposer can disable the offer");
            assert!(borrowing_offer.is_active, "The borrowing offer is not active");

            // Update the borrowing offer status
            borrowing_offer.is_active = false;
            self.all_borrowing_offers.at(offer_id).write(borrowing_offer);
        }
        fn withdraw_collateral(ref self: ContractState, collateral_id: u64) {
            let borrower = get_caller_address();
            let mut collateral: Collateral = self.all_collateral_user.entry(borrower).at(collateral_id).read();
            assert!(collateral.is_active, "Collateral has already been withdrawn");
            assert!(borrower == collateral.owner, "Only the owner can withdraw the collateral");
            // Check if no borrow is made with this collateral
            assert!(collateral.available_value == collateral.total_value, "The collateral is used, disable it and wait for the end of your loans");

            // Remove the collateral
            let erc20 = IERC20Dispatcher { contract_address: collateral.token };
            erc20.transfer(borrower, collateral.deposited_amount);

            // Update the borrowing offer status
            collateral.is_active = false;
            collateral.deposited_amount = 0;
            self.all_collateral_user.entry(borrower).at(collateral_id).write(collateral);
        }

        // @dev: amount is the amount in 10**18 scale we lend that get transfer to the borrower at the end of this function
        fn match_offer(ref self: ContractState, lending_offer_id: u64, borrowing_offer_id: u64, amount: u256) {
            let mut lending_offer = self.all_lending_offers.at(lending_offer_id).read();
            let lent_token = lending_offer.token;
            let mut borrowing_offer = self.all_borrowing_offers.at(borrowing_offer_id).read();
            
            assert!(lending_offer.is_active, "The lending offer is not active");
            assert!(borrowing_offer.is_active, "The borrowing offer is not active");
            if borrowing_offer.is_allowance {
                self.me.write(true);
                self.from_borrowing_allowance_offer_to_borrowing_deposit_offer(borrowing_offer_id);
                self.me.write(false);
                // Re-read the updated offer
                borrowing_offer = self.all_borrowing_offers.at(borrowing_offer_id).read();
            }
            let mut collateral: Collateral = self.all_collateral_user.entry(borrowing_offer.proposer).at(borrowing_offer.collateral_id).read();
            assert!(collateral.is_active, "The collateral is not active (aka has been withdrawn already)");
            let collateral_token = collateral.token;

            assert!(category_id_from_address(lent_token) == category_id_from_address(collateral_token),
                    "Both offer are not of the same category (eg one is eth market and the other is usdc market");
            // APR check
            assert!(borrowing_offer.price.rate >= constants::APR_1_PERCENT + lending_offer.price.rate,
                "Offer price are not compatible, you need borrow_rate - lending_rate >= 1percent (platform fee)");

            assert!(amount <= lending_offer.amount_available, "Not enough demand available in the lending offer");
            assert!(amount <= borrowing_offer.amount_available, "Not enough demand available in the borrowing offer");

            // Create a new match
            let price_match = Price {
                rate: lending_offer.price.rate,
                // More flexibility for the borrower to do that instead of max2(lending.min, borrower.min)
                // And it's essentially the same because it's the borrower that choose to repay, not the lender
                // Todo, now it's max2 but let do something better in the future
                minimal_duration: max2(lending_offer.price.minimal_duration, borrowing_offer.price.minimal_duration),
                // This give less flexibility to the borrower, but takes less of its collateral
                // as the amount of collateral is based on the maximal length of the loan
                // A taker borrower is therefore free to choose whatever value he prefers for this min
                // And a maker borrower needs to be careful because this duration can be choosen arbitraly small
                maximal_duration: min2(lending_offer.price.maximal_duration, borrowing_offer.price.maximal_duration)
            };
            assert_validity_of_price(price_match);
            let current_date = get_block_timestamp();
            let new_match = Match {
                id: self.all_current_match.len(),
                lending_offer_id,
                borrowing_offer_id,
                is_active: true,
                date_taken: current_date,
                amount,
                lending_rate: lending_offer.price.rate,
                borrowing_rate: borrowing_offer.price.rate,
                minimal_duration: price_match.minimal_duration,
                maximal_duration: price_match.maximal_duration
            };
            let max_to_repay = max_to_repay(new_match);
            assert!(max_to_repay <= collateral.available_value, "Not enough collateral available in the collateral");
            self.all_current_match.append().write(new_match);

            // Transfer the asset to the borrower
            let lender = lending_offer.proposer;
            let borrower = borrowing_offer.proposer;
            let erc20 = IERC20Dispatcher { contract_address: lending_offer.token };
            let amount_to_transfer = inverse_scale_to_18_decimals(lending_offer.token, amount);
            erc20.transferFrom(lender, borrower, amount_to_transfer);

            // Update the lending offer and borrowing offer status
            lending_offer.amount_available -= amount;
            borrowing_offer.amount_available -= amount;
            // It's max_to_repay because that's the maximal debt we can possibly have with this position
            collateral.available_value -= max_to_repay;

            // Store in memory
            self.all_lending_offers.at(lending_offer_id).write(lending_offer);
            self.all_borrowing_offers.at(borrowing_offer_id).write(borrowing_offer);
            self.all_collateral_user.entry(borrowing_offer.proposer).at(borrowing_offer.collateral_id).write(collateral);
        }
        fn repay_debt(ref self: ContractState, match_offer_id: u64) {
            let mut match_offer = self.all_current_match.at(match_offer_id).read();
            assert!(match_offer.is_active, "The match offer is not active");
            
            let mut lending_offer = self.all_lending_offers.at(match_offer.lending_offer_id).read();
            let mut borrowing_offer = self.all_borrowing_offers.at(match_offer.borrowing_offer_id).read();
            let mut collateral: Collateral = self.all_collateral_user.entry(borrowing_offer.proposer).at(borrowing_offer.collateral_id).read();
            // assert(collateral.is_active, "The collateral is not active, this can't happen");
            let lend_token = lending_offer.token;
            let lender = lending_offer.proposer;
            let borrower = borrowing_offer.proposer;
            let lent_amount = match_offer.amount;

            assert!(borrower == get_caller_address(), "Only the borrower can repay the debt");
            
            // Repay with interest
            let current_date = get_block_timestamp();
            assert_offer_can_be_repay(match_offer, current_date);
            let (interest_lender, fee) = interest_to_repay(match_offer, current_date);
            //println!("Repayment of debt of {} tokens. To repay: {} tokens for the lender, and {} tokens for the fee", match_offer.amount, interest_lender + lent_amount, fee);
            let erc20 = IERC20Dispatcher { contract_address: lend_token };
            erc20.transferFrom(get_caller_address(), lender, inverse_scale_to_18_decimals(lend_token, interest_lender + lent_amount));
            erc20.transferFrom(get_caller_address(), get_contract_address(), inverse_scale_to_18_decimals(lend_token, fee));

            // Points - add to lender and borrower the amount of fee paid
            let mut multiplier = self.points_multiplier.read();
            // Strk price is .5$, so we divide the multiplier by 2 compared to the usdc market where assets have a price of 1$
            // Todo, do it for eth too when eth market is opened - and rework that section at that time
            if (category_id_from_address(lend_token) == STRK_CATEGORY) {
                multiplier = multiplier / 2;
            }
            self.total_points.write(self.total_points.read() + 2 * fee * multiplier);
            self.user_points.entry(lender).write(self.user_points.entry(lender).read() + fee * multiplier);
            self.user_points.entry(borrower).write(self.user_points.entry(borrower).read() + fee * multiplier);

            // Remove the match, re-add amount to the offers
            match_offer.is_active = false;
            self.all_current_match.at(match_offer_id).write(match_offer);

            // Relist the lending_offers and borrowing_offers
            // The lending offer auto compounds by default, hence the `+ lent_amount`
            lending_offer.amount_available += interest_lender + lent_amount;
            lending_offer.total_amount += interest_lender;
            borrowing_offer.amount_available += lent_amount;
            collateral.available_value += max_to_repay(match_offer);
            self.all_lending_offers.at(match_offer.lending_offer_id).write(lending_offer);
            self.all_borrowing_offers.at(match_offer.borrowing_offer_id).write(borrowing_offer);
            self.all_collateral_user.entry(borrowing_offer.proposer).at(borrowing_offer.collateral_id).write(collateral);
        }

        fn liquidate(ref self: ContractState, match_offer_id: u64) {
            let mut match_offer = self.all_current_match.at(match_offer_id).read();
            assert!(match_offer.is_active, "The match offer is not active");
            let current_date = get_block_timestamp();
            assert!(current_date > match_offer.date_taken + match_offer.maximal_duration, "Loan cannot be liquidated yet");
            // Search for all offers that use this collateral
            let borrow_offer = self.all_borrowing_offers.at(match_offer.borrowing_offer_id).read();
            let collateral = self.all_collateral_user.entry(borrow_offer.proposer).at(borrow_offer.collateral_id).read();
            let mut affected_lenders: Array<(ContractAddress, u256)> = array![];
            let mut total_affected_amount: u256 = 0;
            let mut all_current_match_id = 0;
            let all_current_match_size = self.all_current_match.len();
            // We loop on all these offers to search for how much we need to pay to who
            // - we store these informations in affected_lenders
            // Todo one day do smth better than looping on everything
            while all_current_match_id < all_current_match_size {
                let mut other_match = self.all_current_match.at(all_current_match_id).read();
                if other_match.is_active {
                    let other_borrow_offer = self.all_borrowing_offers.at(other_match.borrowing_offer_id).read();
                    if (other_borrow_offer.proposer == borrow_offer.proposer) && (other_borrow_offer.collateral_id == borrow_offer.collateral_id) {
                        let lender = self.all_lending_offers.at(other_match.lending_offer_id).read().proposer;
                        let max_to_repay = max_to_repay(other_match);
                        total_affected_amount += max_to_repay;
                        affected_lenders.append((lender, max_to_repay));
                        other_match.is_active = false;
                        self.all_current_match.at(all_current_match_id).write(other_match);
                    }
                }
                all_current_match_id += 1;
            };
            // TESTING - remove the next 4 lines in prod
            println!("Information about the collateral: {:?}", collateral);
            println!("Total amount {}, available amount {}, the difference {}", collateral.total_value, collateral.available_value, collateral.total_value - collateral.available_value);
            println!("Total affected amount: {}", total_affected_amount);
            assert!(total_affected_amount == collateral.available_value, "Pouet");

            // We redistribute the rest of the collateral to the borrower because if a collateral of 1000$ is used to secure a loan of 1$
            // - we do not want to give the whole collateral to the lender in case of default
            affected_lenders.append((borrow_offer.proposer, collateral.total_value - total_affected_amount));

            // Liquidate the collateral, and distribute it equally between lenders
            // to_distribute is the list of erc20 we need to redistribute to the lenders
            let to_distribute = liquidate_collateral(collateral.token, collateral.deposited_amount);
            for (address_lender, amount_lender) in affected_lenders {
                let to_distribute_len = to_distribute.len();
                let mut to_distribute_id = 0;
                while to_distribute_id < to_distribute_len {
                    let (address_repay, amount_repay) = *to_distribute.at(to_distribute_id);
                    // Due to rounding, we pay less than excepted, which is good because every repay can then be processed
                    // - the last one won't have a problem
                    // Because the ltv is not 100%, lenders will in the end get more than what they lent
                    // - indeed, collateral value are smth like `ltv% * price` which is stricly less than their real value
                    // - so a loan of 100$ secured by a collateral of value 100$ will end up with this collateral that
                    // - has a real world value of something like 100$ / ltv% which is stricly greater than 100$
                    IERC20Dispatcher { contract_address: address_repay }.transfer(address_lender, amount_repay * amount_lender / total_affected_amount);
                    to_distribute_id += 1;
                }
                // Somehow doesn't work to embricate two for loops, hence this comment and the while loop above
                // for (address_repay, amount_repay) in to_distribute {
                //     IERC20Dispatcher { contract_address: address_repay }.transfer(address_lender, amount_repay * amount_lender / total_affected_amount);
                // }
            }
        }

        fn set_price(ref self: ContractState, address: ContractAddress, price: u256) {
            assert_is_admin();
            self.price_information.write(address, price);
        }
        fn set_ltv(ref self: ContractState, address: ContractAddress, ltv: u256) {
            assert_is_admin();
            self.ltv_information.write(address, ltv);
        }

        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert_is_admin();
            replace_class_syscall(new_class_hash).unwrap();
        }




        // Frontend functions - all read only - only used in the frontend, never in the contract code
        // THE BELOW CODE IS NOT TESTED, I reserve the right to change these functions, including
        // but not only return wrong values, delete them, change their arguments etc... - use them at risk
        // THE BELOW CODE IS NOT PART OF ANY AUDIT SCOPE, I decline any responssabilities regarding
        // the eventual correctness of them - use them at risk
        
        // From an offer, check what the user can actually pay, aka: allowance, its balance, and what the offer permits
        fn frontend_actual_lending_amount(self: @ContractState, offer_id: u64) -> u256 {
            let lending_offer = self.all_lending_offers.at(offer_id).read();
            let lender = lending_offer.proposer;
            let erc20 = IERC20Dispatcher { contract_address: lending_offer.token };
            let value1 = scale_to_18_decimals(lending_offer.token, erc20.allowance(lender, get_contract_address()));
            let value2 = scale_to_18_decimals(lending_offer.token, erc20.balanceOf(lender));
            let value3 = lending_offer.amount_available;
            return min3(value1, value2, value3);
        }
        fn frontend_actual_borrowing_amount(self: @ContractState, offer_id: u64) -> u256 {
            let borrowing_offer = self.all_borrowing_offers.at(offer_id).read();
            let borrower = borrowing_offer.proposer;
            if borrowing_offer.is_allowance {
                let token = borrowing_offer.token_collateral;
                let erc20 = IERC20Dispatcher { contract_address: token };
                let value1 = min2_256(
                    compute_value_of_asset(self, erc20.allowance(borrower, get_contract_address()), token),
                    compute_value_of_asset(self, erc20.balanceOf(borrower), token)
                );
                let value2 = compute_value_of_asset(self, borrowing_offer.amount_collateral, token);
                let value3 = borrowing_offer.amount_available;
                return min3(value1, value2, value3);
            }
            // Doesn't want to compile with this else, hence the comment
            //else {
                let collateral = self.all_collateral_user.entry(borrower).at(borrowing_offer.collateral_id).read();
                let value1 = collateral.available_value;
                let value2 = borrowing_offer.amount_available;
                return min2_256(value1, value2);
            //};
        }
        
        // Return all current and actual offer based on what the user can pay
        fn frontend_get_all_offers(self: @ContractState, category: felt252) -> (Span<BorrowingOffer>, Span<LendingOffer>) {
            let mut borrowing = array![];
            let mut i_borrowing = 0;
            let borrowing_offer_size = self.all_borrowing_offers.len();
            while i_borrowing < borrowing_offer_size {
                let mut offer = self.all_borrowing_offers.at(i_borrowing).read();
                if offer.is_active {
                    if category_id_from_address(offer.token_collateral) == category {
                        offer.amount_available = self.frontend_actual_borrowing_amount(i_borrowing);
                        borrowing.append(offer);
                    }
                }
                i_borrowing += 1;
            };
            let mut lending = array![];
            let mut i_lending = 0;
            let lending_offer_size = self.all_lending_offers.len();
            while i_lending < lending_offer_size {
                let mut offer = self.all_lending_offers.at(i_lending).read();
                if offer.is_active {
                    if category_id_from_address(offer.token) == category {
                        offer.amount_available = self.frontend_actual_lending_amount(i_lending);
                        lending.append(offer);
                    }
                }
                i_lending += 1;
            };
            (borrowing.span(), lending.span())
        }
        // Return (max_borrow_yield, min_lend_yield)
        fn frontend_best_available_yield(self: @ContractState, category: felt252) -> (u256, u256) {
            let (all_borrow, all_lend) = self.frontend_get_all_offers(category);
            let mut max_yield_borrow = constants::MIN_APR;
            for borrow_offer in all_borrow {
                if *borrow_offer.price.rate > max_yield_borrow && *borrow_offer.amount_available >= constants::VALUE_1e18 {
                    max_yield_borrow = *borrow_offer.price.rate;
                }
            };
            let mut max_yield_lend = constants::MAX_APR;
            for lend_offer in all_lend {
                if *lend_offer.price.rate < max_yield_lend && *lend_offer.amount_available >= constants::VALUE_1e18 {
                    max_yield_lend = *lend_offer.price.rate;
                }
            };
            (max_yield_borrow, max_yield_lend)
        }
        // Return (sum(available_borrow_volume), sum(available_lend_volume))
        fn frontend_available_to_lend_and_borrow(self: @ContractState, category: felt252) -> (u256, u256) {
            let (all_borrow, all_lend) = self.frontend_get_all_offers(category);
            let mut available_to_borrow = 0;
            for borrow_offer in all_borrow {
                available_to_borrow += self.frontend_actual_borrowing_amount(*borrow_offer.id);
            };
            let mut available_to_lend = 0;
            for lend_offer in all_lend {
                available_to_lend += self.frontend_actual_lending_amount(*lend_offer.id);
            };
            (available_to_borrow, available_to_lend)
        }
        
        fn frontend_get_all_lending_offers_of_user(self: @ContractState, category: felt252, user: ContractAddress) -> Span<LendingOffer> {
            let mut user_lending_offers = array![];
            let lending_offer_size = self.all_lending_offers.len();
            let mut i_lending = 0;
            while i_lending < lending_offer_size {
                let offer = self.all_lending_offers.at(i_lending).read();
                if offer.is_active {
                    if offer.proposer == user && category_id_from_address(offer.token) == category {
                        user_lending_offers.append(offer);
                    }
                }
                i_lending += 1;
            };
            user_lending_offers.span()
        }
        
        fn frontend_get_all_borrowing_offers_of_user(self: @ContractState, category: felt252, user: ContractAddress) -> Span<BorrowingOffer> {
            let mut user_borrowing_offers = array![];
            let borrowing_offer_size = self.all_borrowing_offers.len();
            let mut i_borrowing = 0;
            while i_borrowing < borrowing_offer_size {
                let offer = self.all_borrowing_offers.at(i_borrowing).read();
                if offer.is_active {
                    if offer.proposer == user && category_id_from_address(offer.token_collateral) == category {
                        user_borrowing_offers.append(offer);
                    }
                }
                i_borrowing += 1;
            };
            user_borrowing_offers.span()
        }
        
        // First return value is loans when we are borrowers - second is lender
        // The second value of each tuple is the token of the loan
        fn frontend_get_all_matches_of_user(self: @ContractState, category: felt252, user: ContractAddress) -> (Span<(Match, ContractAddress)>, Span<(Match, ContractAddress)>) {
            let mut user_matches_borrowing = array![];
            let mut user_matches_lending = array![];
            let match_size = self.all_current_match.len();
            let mut i_match = 0;
            while i_match < match_size {
                let match_offer = self.all_current_match.at(i_match).read();
                let lending_offer = self.all_lending_offers.at(match_offer.lending_offer_id).read();
                let borrowing_offer = self.all_borrowing_offers.at(match_offer.borrowing_offer_id).read();
                if match_offer.is_active { 
                    if category_id_from_address(lending_offer.token) == category {
                        if borrowing_offer.proposer == user {
                            user_matches_borrowing.append((match_offer, lending_offer.token));
                        }
                        if lending_offer.proposer == user {
                            user_matches_lending.append((match_offer, lending_offer.token));
                        }
                    }
                }
                i_match += 1;
            };
            (user_matches_borrowing.span(), user_matches_lending.span())
        }
        
        fn frontend_get_all_collaterals_of_user(self: @ContractState, category: felt252, user: ContractAddress) -> Span<Collateral> {
            let mut user_collaterals = array![];
            let collaterals = self.all_collateral_user.entry(user);
            let collaterals_size = collaterals.len();
            let mut i_collateral = 0;
            while i_collateral < collaterals_size {
                let collateral = collaterals.at(i_collateral).read();
                if collateral.is_active {
                    if category_id_from_address(collateral.token) == category {
                        user_collaterals.append(collateral);
                    }
                }
                i_collateral += 1;
            };
            user_collaterals.span()
        }

        // Points
        // All of these 3 functions are part of the frontend functions - the same disclaimers written above apply
        fn frontend_get_user_points(self: @ContractState, user: ContractAddress) -> u256 {
            self.user_points.read(user)
        }
        fn frontend_get_total_points(self: @ContractState) -> u256 {
            self.total_points.read()
        }
        fn set_points_multiplier(ref self: ContractState, multiplier: u256) {
            assert_is_admin();
            self.points_multiplier.write(multiplier);
        }
    }
}