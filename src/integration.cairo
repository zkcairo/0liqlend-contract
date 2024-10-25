// A function is in this file if and only if there is something to be done when we add a new integrations to the protocol

use starknet::ContractAddress;
use mycode::mock_erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
use mycode::utilities::pow;
use mycode::constants;

// Return a value that is used purely to compare with other result of this function
// This function will be more complex when dealing with more complex assets
// @dev: amount: amount of the asset, not scaled or anything
// @dev: price_of_assets: how much 10**18 worth of asset is worth - scaled to 10**18
// @dev: ltv: is in %, with a scale 10000; So 100% is 10000, and 99% is 9900, 99.9% is 9990
// Return into 10**18 scale - so 1USDC is worth 10**18 with this function
// Tested in file utilities_test.cairo
pub fn aux_compute_value_of_asset(amount: u256, asset: IERC20Dispatcher, price_of_asset: u256, ltv: u256) -> u256 {
    // Right now: only nimbora assets
    let value = amount;
    let value = value * price_of_asset; // price_of_assets it scaled to 10**18, that's why we divide 3 lines later by 10**18
    let value = value * ltv / constants::LTV_SCALE;
    let value = value;
    let value_10e18 = 1000000000000000000;
    value / value_10e18
}

pub fn category_id_from_address(_address: ContractAddress) -> felt252 {
    let address: felt252 = _address.into();
    // Regular assets
    if address == constants::ETH_ADDRESS {
        return constants::ETH_CATEGORY;
    } else if address == constants::USDC_ADDRESS || address == constants::DAI_ADDRESS || address == constants::DAIV0_ADDRESS {
        return constants::USDC_CATEGORY;
    } else if address == constants::STRK_ADDRESS {
        return constants::STRK_CATEGORY;
    }
    // Nimbora assets
    // Pendle eth
    // else if address == constants::NIMBORA_npeETH_ADDRESS || address == constants::NIMBORA_nppETH_ADDRESS {
    //     return constants::ETH_CATEGORY;
    // }
    // Pendle usdc
    // else if address == constants::NIMBORA_npaUSDT_ADDRESS || address == constants::NIMBORA_npfUSDC_ADDRESS  {
    //     return constants::USDC_CATEGORY;
    // }
    // Wrappers around dai and usda
    else if address == constants::NIMBORA_nsDAI_ADDRESS || address == constants::NIMBORA_nstUSD_ADDRESS {
        return constants::USDC_CATEGORY;
    }
    // Other integration will be here
    // Otherwise, not found: fail
    // TESTING - comment the 1st/uncomment 2nd & 3rd in prod
    return 7;
    // assert!(false, "This token is not supported");
    // return 0;
}

// Take a collateral, and liquidate it to make it fungible
// Returns a list of (erc20, amount) that we can redistribute to lenders
pub fn liquidate_collateral(address: ContractAddress, amount: u256) -> Array<(ContractAddress, u256)> {
    // For now, we only work with erc20 tokens, so nothing to do
    // Todo maybe do something else
    return array![(address, amount)];
}