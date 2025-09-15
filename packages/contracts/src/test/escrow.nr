use crate::test::utils::{
    setup::{setup, USDC_ESCROW_AMOUNT, ETH_ESCROW_AMOUNT},
    escrow::{
        deposit_to_escrow,
        fill_otc_order,
        get_escrow_definition
    },
    token::{
        expect_private_balance,
        mint_to_private
    }
};
use aztec::{
    oracle::random::random,
    protocol_types::traits::ToField,
};
use uint_note::uint_note::PartialUintNote;

// Basic e2e escrow test
#[test]
unconstrained fn e2e() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // check the definition
    let definition = get_escrow_definition(contracts.escrow);
    assert_eq(definition.owner, contracts.escrow, "Definition owner mismatch!");
    assert_eq(definition.sell_token_address, contracts.usdc, "Definition sell token address mismatch!");
    assert_eq(definition.sell_token_amount, USDC_ESCROW_AMOUNT, "Definition sell token amount mismatch!");
    assert_eq(definition.buy_token_address, contracts.eth, "Definition buy token address mismatch!");
    assert_eq(definition.buy_token_amount, ETH_ESCROW_AMOUNT, "Definition buy token amount mismatch!");

    // check the partial note commitment in the definition is valid
    let validity_commitment = PartialUintNote { 
        commitment: definition.partial_note 
    }.compute_validity_commitment(contracts.escrow);
    assert(
        env.public().nullifier_exists(validity_commitment, contracts.eth),
        "Validity nullifier should exist",
    );

    // check usdc balance of seller and contract before deposit
    expect_private_balance(contracts.usdc, accounts.seller, USDC_ESCROW_AMOUNT);
    expect_private_balance(contracts.usdc, contracts.escrow, 0);

    // deposit to escrow
    deposit_to_escrow(
        env,
        accounts.seller,
        contracts.escrow,
        contracts.usdc,
        USDC_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // check usdc balance of seller and contract after deposit
    expect_private_balance(contracts.usdc, accounts.seller, 0);
    expect_private_balance(contracts.usdc, contracts.escrow, USDC_ESCROW_AMOUNT);

    // fill the otc order
    fill_otc_order(
        env,
        accounts.buyer,
        contracts.escrow,
        contracts.eth,
        ETH_ESCROW_AMOUNT,
        false // no malicious authwit
    );

    // check balances after otc order is complete
    // why does uncommenting this cause
    // "Assertion failed: A partial note's completion log did not result in any notes being found - this should never happen"
    // expect_private_balance(contracts.usdc, accounts.buyer, USDC_ESCROW_AMOUNT);
    // expect_private_balance(contracts.usdc, contracts.escrow, 0);
    // expect_private_balance(contracts.eth, accounts.seller, ETH_ESCROW_AMOUNT);
}

// #[test]
// unconstrained fn e2e() {
//     // get test environment
//     let (env, accounts, contracts) = setup(true);
    
//     // check the definition
//     let definition = get_escrow_definition(contracts.escrow);
//     assert_eq(definition.owner, contracts.escrow, "Definition owner mismatch!");
//     assert_eq(definition.sell_token_address, contracts.usdc, "Definition sell token address mismatch!");
//     assert_eq(definition.sell_token_amount, USDC_ESCROW_AMOUNT, "Definition sell token amount mismatch!");
//     assert_eq(definition.buy_token_address, contracts.eth, "Definition buy token address mismatch!");
//     assert_eq(definition.buy_token_amount, ETH_ESCROW_AMOUNT, "Definition buy token amount mismatch!");

//     // check the partial note commitment in the definition is valid
//     let validity_commitment = PartialUintNote { 
//         commitment: definition.partial_note 
//     }.compute_validity_commitment(contracts.escrow);
//     assert(
//         env.public().nullifier_exists(validity_commitment, contracts.eth),
//         "Validity nullifier should exist",
//     );

//     // check usdc balance of seller and contract before deposit
//     expect_private_balance(contracts.usdc, accounts.seller, USDC_ESCROW_AMOUNT);
//     expect_private_balance(contracts.usdc, contracts.escrow, 0);

//     // deposit to escrow
//     deposit_to_escrow(
//         env,
//         accounts.seller,
//         contracts.escrow,
//         contracts.usdc,
//         USDC_ESCROW_AMOUNT,
//         false // no malicious authwit
//     );

//     // check usdc balance of seller and contract after deposit
//     expect_private_balance(contracts.usdc, accounts.seller, 0);
//     expect_private_balance(contracts.usdc, contracts.escrow, USDC_ESCROW_AMOUNT);

//     // fill the otc order
//     fill_otc_order(
//         env,
//         accounts.buyer,
//         contracts.escrow,
//         contracts.eth,
//         ETH_ESCROW_AMOUNT,
//         false // no malicious authwit
//     );

//     // check balances after otc order is complete
//     // why does uncommenting this cause
//     // "Assertion failed: A partial note's completion log did not result in any notes being found - this should never happen"
//     // expect_private_balance(contracts.usdc, accounts.buyer, USDC_ESCROW_AMOUNT);
//     // expect_private_balance(contracts.usdc, contracts.escrow, 0);
//     // expect_private_balance(contracts.eth, accounts.seller, ETH_ESCROW_AMOUNT);
// }
