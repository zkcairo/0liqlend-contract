use starknet::ContractAddress;

#[cfg(test)]
pub mod utilities_tests {
    // From the contract
    use mycode::constants;
    use mycode::utilities::{ min3, min2, min2_256, max2, scale_to_18_decimals, inverse_scale_to_18_decimals };
    use mycode::mock_erc20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    use starknet::ContractAddress;
    use snforge_std::{ declare, ContractClassTrait };

    fn deploy_erc20(decimals: felt252) -> (IERC20Dispatcher, ContractAddress) {
        let contract = declare("mock_erc20").unwrap();
        let mut constructor_calldata = array![decimals];
        let (contract_address, _) = contract.deploy(@constructor_calldata).unwrap();
        let dispatcher = IERC20Dispatcher { contract_address: contract_address };
        (dispatcher, contract_address)
    }

    #[test]
    fn test_min2(a: u64, b: u64) {
        if a > b {
            assert_eq!(min2(a, b), b);
        }
        else {
            assert_eq!(min2(a, b), a);
        }
    }
    #[test]
    fn test_min2_256(a: u256, b: u256) {
        if a > b {
            assert_eq!(min2_256(a, b), b);
        }
        else {
            assert_eq!(min2_256(a, b), a);
        }
    }

    #[test]
    fn test_max2(a: u64, b: u64) {
        if a > b {
            assert_eq!(max2(a, b), a);
        }
        else {
            assert_eq!(max2(a, b), b);
        }
    }

    #[test]
    fn test_min3_1(_a: u128, _b: u128, _c: u128) {
        let a: u256 = _a.into();
        let b: u256 = _b.into();
        let c: u256 = _c.into();
        let first = a;
        let second = a+b;
        let third = a+b+c;
        assert_eq!(min3(first, second, third), first);
    }

    #[test]
    fn test_min3_2(a: u256, b: u256, c: u256) {
        assert_le!(min3(a, b, c), a);
        assert_le!(min3(a, b, c), b);
        assert_le!(min3(a, b, c), c);
    }

    // u128 because otherwise it overflows!
    #[test]
    fn test_scale_decimals(amount: u128, _decimals: felt252) {
        let decimals: u256 = _decimals.into();
        let decimals = 1 + (decimals % 17);
        let (_, erc20) = deploy_erc20(decimals.try_into().unwrap());
        let scaled_amount = scale_to_18_decimals(erc20, amount.into());
        let unscaled_amount = inverse_scale_to_18_decimals(erc20, scaled_amount);
        assert_eq!(amount.into(), unscaled_amount);
    }
}