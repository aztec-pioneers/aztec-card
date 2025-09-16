use crate::{
    CardEscrow,
    test::utils::{
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT},
        card_escrow::{
            deposit,
            get_config,
            spend_from_escrow,
            compute_epoch,
            prepare_withdrawal,
            withdraw
        },
        token::{
            expect_private_balance,
            mint_to_private
        }
    }
};
use aztec::{
    oracle::{random::random, execution::get_timestamp},
    protocol_types::traits::ToField,
    test::helpers::cheatcodes
};

// Basic e2e escrow test
#[test]
unconstrained fn e2e() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // check config
    let config = get_config(contracts.card_escrow);
    assert_eq(config.owner, contracts.card_escrow, "Config owner mismatch!");
    assert_eq(config.token_address, contracts.usdc, "Config token address mismatch!");
    assert_eq(config.operator_address, accounts.operator, "Config operator address mismatch!");
    assert_eq(config.user_address, accounts.user, "Config user address mismatch!");
    assert_eq(config.spend_limit, INITIAL_SPEND_LIMIT, "Config spend limit mismatch!");

    // deposit to escrow
    deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // check usdc balance of user and contract after deposit
    expect_private_balance(contracts.usdc, accounts.user, 0);
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT);

    // spend from escrow twice in same epoch
    let mut epoch = compute_epoch();
    spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2,
        epoch,
        true // first spend in this epoch
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT / 2));
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT / 2);
    spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2,
        epoch,
        false // subsequent spend in this epoch
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - INITIAL_SPEND_LIMIT);
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT);

    // advance epoch
    cheatcodes::advance_timestamp_by(86400);
    assert(compute_epoch() == epoch + 1, "Epoch should have advanced by 1");
    epoch = epoch + 1;
    // spend from escrow in new epoch
    spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
        true // subsequent spend in this epoch
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2));
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT * 2);

    // withdraw from escrow
    prepare_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2)
    );
    // advance past timelock 
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);
    withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, 0);
    expect_private_balance(contracts.usdc, accounts.user, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2));
}

// try to overspend from limit
// check switching spend limit
// 