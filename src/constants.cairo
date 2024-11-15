use starknet::ContractAddress;

// Address
pub const ADMIN_ADDRESS: felt252 = 0x07d25449d864087e8e1ddbd237576c699dfe0ea98979d920fcf84dbd92a49e10;

//////////////////////////////////////////
// ETH
//////////////////////////////////////////
pub const ETH_CATEGORY: felt252 = -1;
// Regular assets
pub const ETH_ADDRESS: felt252 = 0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7;
// Nimbora assets
pub const NIMBORA_npeETH_ADDRESS: felt252 = 0x316ec509f7ad89b7e6e03d15a436df634454f95e815536d616af03edc850fa3;

////////////////////////////////////////////
// USDC
////////////////////////////////////////////
pub const USDC_CATEGORY: felt252 = -2;
// Regular assets
pub const USDT_ADDRESS: felt252 = 0x068f5c6a61780768455de69077e07e89787839bf8166decfbf92b645209c0fb8;
pub const USDC_ADDRESS: felt252 = 0x053c91253bc9682c04929ca02ed00b3e423f6710d2ee7e0d5ebb06f3ecf368a8;
pub const DAI_ADDRESS: felt252 = 0x05574eb6b8789a91466f902c380d978e472db68170ff82a5b650b95a58ddf4ad;
pub const DAIV0_ADDRESS: felt252 = 0x00da114221cb83fa859dbdb4c44beeaa0bb37c7537ad5ae66fe5e0efd20e6eb3;
// Nimbora assets
pub const NIMBORA_nsDAI_ADDRESS: felt252 = 0x004380de5819e2e989b5e8b978ea2811fd36fdbc5c12fcfb3a2b444098888665;
pub const NIMBORA_nstUSD_ADDRESS: felt252 = 0x0405b7b5fb7353ec745d9ef7cf1634e54fd25c5e24d62241c177114a18c45910;

////////////////////////////////////////////
// STRK
////////////////////////////////////////////
pub const STRK_CATEGORY: felt252 = -3;
// Regular assets
pub const STRK_ADDRESS: felt252 = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
// Liquid stacking providers:
// Nimbora
pub const sSTRK: felt252 = 0x01f823d93f9b5a836a3a1a4cea64bfb5737db81270cd526201a82d7447691cf9;
// Nostra
pub const nstStrk: felt252 = 0x04619e9ce4109590219c5263787050726be63382148538f3f936c22aa87d2fc2;
// Strk farm
// Todo


// Values
// Time
pub const SECONDS_PER_HOUR: u64 = 3600;
pub const SECONDS_PER_DAY: u64 = 86400;
pub const SECONDS_PER_YEAR: u64 = 31536000; // To simplify we assume we have only 365days, but it's actually 365.25 in reality
pub const MIN_TIME_SPACING_FOR_OFFERS: u64 = SECONDS_PER_DAY;
// APY
pub const APR_1_PERCENT: u256 = 10000;
pub const APR_SCALE: u256     = APR_1_PERCENT * 100; // Used in compute_interest
pub const MIN_APR: u256 = APR_1_PERCENT / 100;       // 0.01%
pub const MAX_APR: u256 = APR_1_PERCENT * 1000;      // 1000%
// LTV
pub const LTV_SCALE: u256 = 10000;
pub const LTV_100_PERCENT: u256 = LTV_SCALE;
pub const LTV_50_PERCENT: u256 = LTV_SCALE / 2;
pub const LTV_10_PERCENT: u256 = LTV_SCALE / 10;
pub const LTV_1_PERCENT: u256  = LTV_SCALE / 100;
// Constants
pub const VALUE_1e18: u256 = 1000000000000000000;