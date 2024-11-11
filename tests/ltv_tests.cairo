// Test of integration.cairo

use starknet::ContractAddress;

#[cfg(test)]
pub mod ltv_tests {
    // From the contract
    use mycode::{ IMyCodeDispatcher, IMyCodeDispatcherTrait };
    use mycode::mock_erc20::{ IERC20Dispatcher, IERC20DispatcherTrait };
    use mycode::datastructures::{ LendingOffer, BorrowingOffer, Price, Match, Collateral };
    use mycode::constants;
    use mycode::integration::aux_compute_value_of_asset;
    // Forge and starknet imports
    use snforge_std::{ declare, ContractClassTrait, BlockId, CheatSpan, start_cheat_caller_address, cheat_caller_address, start_cheat_block_timestamp_global };
    use starknet::{ContractAddress, contract_address_const, get_block_timestamp };

    // Deploy 2 erc contracts with each a different decimal value
    fn deploy_erc20(decimals1: felt252, decimals2: felt252) -> Span<(IERC20Dispatcher, ContractAddress)> {
        let contract = declare("mock_erc20").unwrap();
        let mut constructor_calldata_1 = array![decimals1];
        let (contract_address_1, _) = contract.deploy(@constructor_calldata_1).unwrap();
        let dispatcher_1 = IERC20Dispatcher { contract_address: contract_address_1 };
        let mut constructor_calldata_2 = array![decimals2];
        let (contract_address_2, _) = contract.deploy(@constructor_calldata_2).unwrap();
        let dispatcher_2 = IERC20Dispatcher { contract_address: contract_address_2 };
        array![(dispatcher_1, contract_address_1), (dispatcher_2, contract_address_2)].span()
    }
    
    #[test]
    fn test_compute_value_asset(amount: u128) {
        let arr = deploy_erc20(6, 18);
        let (erc20_6, _) = *arr[0];
        let (erc20_18, _) = *arr[1];

        let value_1e6 = 1000000;
        let value_1e12 = 1000000000000;
        let value_1e18 = 1000000000000000000;
        let value_1e18_plus_12 = 1000000000000000000000000000000;
        let ltv = constants::LTV_SCALE;

        assert_eq!(aux_compute_value_of_asset(value_1e6, erc20_6, value_1e18_plus_12, ltv), value_1e18);
        assert_eq!(aux_compute_value_of_asset(value_1e18, erc20_18, value_1e18, ltv), value_1e18);
        assert_eq!(aux_compute_value_of_asset(1, erc20_18, value_1e18, ltv), 1);

        assert_eq!(aux_compute_value_of_asset(amount.into(), erc20_6, value_1e18_plus_12, ltv), amount.into() * value_1e12);
        assert_eq!(aux_compute_value_of_asset(amount.into(), erc20_18, value_1e18, ltv), amount.into());
    }
}