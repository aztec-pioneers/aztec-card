use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT},
        token::expect_private_balance
    }
};
use aztec::test::helpers::cheatcodes;

#[test(should_fail_with = "Assertion failed: Spend limit exceeded!")]
unconstrained fn test_overspend_limit_1_tx_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // try to overspend from a single transaction
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT + 1,
        epoch,
    );
}

#[test(should_fail_with = "Assertion failed: Spend limit exceeded!")]
unconstrained fn test_overspend_limit_2_tx_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // spend exact allowed amount
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );

    // try to overspend by a single unit
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        1,
        epoch,
    );
}

#[test]
unconstrained fn test_switch_spend_limit() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // double spend limit
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // finalize spend limit change
    card_escrow::finalize_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );

    // spend up to the new limit
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2,
        epoch,
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2));
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT * 2);
}

#[test(should_fail_with = "Assertion failed: Spend limit exceeded!")]
unconstrained fn test_switch_spend_limit_down_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // halve spend limit
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // finalize spend limit change
    card_escrow::finalize_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );

    // try to spend original limit
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );
}

#[test]
unconstrained fn test_spend_pending_limt_change() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        USDC_MINT_AMOUNT,
        false // no malicious authwit
    );

    // halve spend limit
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2
    );

    // spend up to the old limit
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);
    // finalize spend limit change
    card_escrow::finalize_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );
}