use starknet::ContractAddress;

#[derive(Copy, Drop, starknet::Store, Serde, Debug, PartialEq)]
pub struct Price {
    pub rate: u256, // See utilities.cairo for the computation of interest to pay
    pub minimal_duration: u64, // In secondes
    pub maximal_duration: u64
}

#[derive(Copy, Drop, starknet::Store, Serde, Debug, PartialEq)]
pub struct LendingOffer {
    pub id: u64,
    pub is_active: bool,
    pub proposer: ContractAddress,
    pub token: ContractAddress,
    pub total_amount: u256,
    pub amount_available: u256, // SCALE TO 10**18 decimals
    pub price: Price,
    pub accepted_collateral: u256, // see token_encoding.cairo
}

#[derive(Copy, Drop, starknet::Store, Serde, Debug, PartialEq)]
pub struct BorrowingOffer {
    pub id: u64,
    pub is_active: bool,
    pub proposer: ContractAddress,
    // What we want to borrow
    pub total_amount: u256, 
    pub amount_available: u256,   // Same - 10**18 decimals
    pub price: Price,
    pub is_allowance: bool,
    // IF TRUE
    pub token_collateral: ContractAddress,
    pub amount_collateral: u256, // Can be 1, because it can be an NFT
    // ELSE
    pub collateral_id: u64,
}

#[derive(Copy, Drop, starknet::Store, Serde, Debug, PartialEq)]
pub struct Match {
    pub id: u64,
    pub is_active: bool,
    pub lending_offer_id: u64,
    pub borrowing_offer_id: u64,
    pub date_taken: u64,
    pub amount: u256,
    pub lending_rate: u256,
    pub borrowing_rate: u256,
    pub minimal_duration: u64,
    pub maximal_duration: u64,
}

#[derive(Copy, Drop, starknet::Store, Serde, Debug, PartialEq)]
pub struct Collateral {
    pub id: u64,
    pub is_active: bool,
    pub owner: ContractAddress, // The borrower
    pub token: ContractAddress,
    pub category: felt252,      // eth, usdc, or strk
    pub deposited_amount: u256, // Can be 1, if it's an NFT - it still has a value thats not 1
    pub total_value: u256,      // The total value of collateral - in 10**18 decimals - fixed on deposit, todo change on each new loan when total_value == available_value
    pub available_value: u256,  // The available value to borrow with this collateral - aka total_value minus what we used to borrow
}