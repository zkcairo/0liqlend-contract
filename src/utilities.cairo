use mycode::datastructures::{LendingOffer, BorrowingOffer, Price, Match, Collateral};
use starknet::{ContractAddress, get_caller_address, contract_address_const};
use mycode::mock_erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use mycode::constants;

// ASSERTS



pub fn assert_is_admin() {
    assert!(get_caller_address().into() == constants::ADMIN_ADDRESS , "Only admin can call this function");
}

// Asset we are within time range of repay
pub fn assert_offer_can_be_repay(match_offer: Match, current_time: u64) {
    assert!(current_time >= match_offer.date_taken + match_offer.minimal_duration, "The offer is not yet repayable");
    assert!(current_time <= match_offer.date_taken + match_offer.maximal_duration, "It's too late to repay!");
}

// Ensure certain requirement on the price offer: the minimal spacing, correct apy, etc...
pub fn assert_validity_of_price(price: Price) {
    // APR check
    // Todo add test so that all price in between is available !! - same for time
    assert!(price.rate >= constants::MIN_APR, "Please lend/borrow at more than 1% APR");
    assert!(price.rate <= constants::MAX_APR, "Please lend/borrow at less than 1000% APR");
    // Time check
    assert!(price.minimal_duration <= price.maximal_duration, "The minimal duration should be less than the maximal duration for the combined match offer");
    let time_diff = price.maximal_duration - price.minimal_duration;
    assert!(time_diff >= constants::MIN_TIME_SPACING_FOR_OFFERS, "Please lend/borrow for at least a day in your offer");
}

// STRK not yet supported
pub fn assert_is_lending_asset(_address: ContractAddress) {
    let address: felt252 = _address.into();
    
    // TESTING - uncomment in prod
    // assert!(address == constants::ETH_ADDRESS || address == constants::USDT_ADDRESS || address == constants::USDC_ADDRESS || address == constants::DAI_ADDRESS || address == constants::DAIV0_ADDRESS,
    //     "Lending offer of only eth usdt usdc dai dai0 are supported atm");
}




// MATH

pub fn min2(a: u64, b: u64) -> u64 {
    if a <= b {
        return a;
    } else {
        return b;
    }
}
pub fn max2(a: u64, b: u64) -> u64 {
    if a >= b {
        return a;
    } else {
        return b;
    }
}
pub fn min2_256(a: u256, b: u256) -> u256 {
    if a <= b {
        return a;
    } else {
        return b;
    }
}
pub fn min3(a: u256, b: u256, c: u256) -> u256 {
    if a <= b && a <= c {
        return a;
    } else if b <= a && b <= c {
        return b;
    } else {
        return c;
    }
}

// base**exp
pub fn pow(base: u256, exp: u256) -> u256 {
    let mut result = 1;
    let mut i: u256 = 0;
    while i < exp {
        result *= base;
        i += 1;
    };
    return result;
}

fn compute_interest(amount: u256, rate: u256, time_diff: u64) -> u256 {
    return amount * rate * time_diff.into() / (constants::SECONDS_PER_YEAR.into() * constants::APR_SCALE.into());
}

// Return (interest of the loan, fee paid to the platform)
pub fn interest_to_repay(match_offer: Match, current_time: u64) -> (u256, u256) {
    let time_diff = current_time - match_offer.date_taken;
    let amount = match_offer.amount;
    let lender_rate = match_offer.lending_rate;
    let fee_rate = match_offer.borrowing_rate - match_offer.lending_rate;
    let interest_lender = compute_interest(amount, lender_rate, time_diff);
    let fee = compute_interest(amount, fee_rate, time_diff);
    return (interest_lender, fee);
}

// Return the maximal amount, interest and fee to repay for a given loan
pub fn max_to_repay(match_offer: Match) -> u256 {
    let max_loan_duration = match_offer.maximal_duration;
    let amount = match_offer.amount;
    let interest_and_fee = compute_interest(amount, match_offer.borrowing_rate, max_loan_duration);
    return amount + interest_and_fee;
}

pub fn scale_to_18_decimals(address: ContractAddress, value: u256) -> u256 {
    let erc20 = IERC20Dispatcher { contract_address: address };
    let decimals: u256 = erc20.decimals().into();
    assert!(decimals <= 18, "Asset with stricly more than 18 decimals are not supported");
    value * pow(10, 18 - decimals)
}
pub fn inverse_scale_to_18_decimals(address: ContractAddress, value: u256) -> u256 {
    let erc20 = IERC20Dispatcher { contract_address: address };
    let decimals: u256 = erc20.decimals().into();
    assert!(decimals <= 18, "Asset with stricly more than 18 decimals are not supported");
    value / pow(10, 18 - decimals)
}