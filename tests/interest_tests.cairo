// Test the interest math

#[cfg(test)]
pub mod interest_tests {
    // Contract
    use mycode::constants;
    use mycode::utilities::interest_to_repay;
    
    // Wrapper around the function of the contract
    use mycode::datastructures::Match;
    fn interest_to_pay(start_time: u64, end_time: u64, amount: u256, rate: u256) -> (u256, u256) {
        let match_offer = Match {
            id: 0, is_active :false, lending_offer_id: 0, borrowing_offer_id: 0, date_taken: start_time, amount: amount, 
            lending_rate: rate, borrowing_rate: rate + constants::APR_1_PERCENT, minimal_duration: 0, maximal_duration: 0
        };
        interest_to_repay(match_offer, end_time)
    }

    #[test]
    fn test_amount_after_a_year(_apy: u256) {
        let start_time = 0;
        let end_time = start_time + constants::SECONDS_PER_YEAR;
        let apy = constants::MIN_APR + (_apy % constants::MAX_APR);
        let rate = apy * constants::APR_1_PERCENT;
        let amount = 10000000;

        let (interest, fee) = interest_to_pay(start_time, end_time, amount, rate);
        let excepted_interest = amount * apy / 100;
        let excepted_fee = amount * 1 / 100;

        assert_eq!(interest, excepted_interest);
        assert_eq!(fee, excepted_fee);
    }

    #[test]
    fn test_amount_after_a_day(_apy: u256) {
        let start_time = 0;
        let end_time = start_time + constants::SECONDS_PER_DAY;
        let apy = constants::MIN_APR + (_apy % constants::MAX_APR);
        let rate = apy * constants::APR_1_PERCENT;
        let amount = 10000000;

        let (interest, fee) = interest_to_pay(start_time, end_time, amount, rate);
        let excepted_interest = amount * apy / 100 / 365; // Number of day in a year - unprecise yes, as in mycode::constants.cairo
        let excepted_fee = amount * 1 / 100 / 365;

        assert_eq!(interest, excepted_interest);
        assert_eq!(fee, excepted_fee);
    }
}