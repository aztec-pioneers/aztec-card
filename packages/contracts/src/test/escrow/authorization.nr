use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT}
    }
};
use aztec::test::helpers::cheatcodes;

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user!")]
unconstrained fn test_cannot_deposit_not_user_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to deposit to escrow from non-user account
    card_escrow::deposit(
       env,
       accounts.external,
       contracts.card_escrow,
       contracts.usdc,
       USDC_MINT_AMOUNT,
       false // no malicious authwit
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user!")]
unconstrained fn test_cannot_change_spend_limit_not_user_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to change spend limit from non-user account
    card_escrow::prepare_forced_spend_limit_change(
        env,
        accounts.external,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user or operator!")]
unconstrained fn test_cannot_finalize_spend_limit_change_not_user_or_operator_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // prepare change spend limit
    card_escrow::prepare_forced_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to finalize spend limit change from non-user account
    card_escrow::finalize_forced_spend_limit_change(
        env,
        accounts.external,
        contracts.card_escrow
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user!")]
unconstrained fn test_cannot_prepare_withdraw_not_user_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit funds to escrow
    card_escrow::deposit(
       env,
       accounts.user,
       contracts.card_escrow,
       contracts.usdc,
       USDC_MINT_AMOUNT,
       false // no malicious authwit
    );

    // try to prepare a withdrawal from non-user account
    card_escrow::prepare_forced_withdrawal(
        env,
        accounts.external,
        contracts.card_escrow,
        USDC_MINT_AMOUNT
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user!")]
unconstrained fn test_cannot_withdraw_not_user_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit funds to escrow
    card_escrow::deposit(
       env,
       accounts.user,
       contracts.card_escrow,
       contracts.usdc,
       USDC_MINT_AMOUNT,
       false // no malicious authwit
    );

    // prepare a withdrawal 
    card_escrow::prepare_forced_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to withdraw from non-user account
    card_escrow::finalize_forced_withdrawal(
        env,
        accounts.external,
        contracts.card_escrow,
        0
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card user!")]
unconstrained fn test_cannot_cancel_timelock_not_user_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to cancel timelock from non-user account
    card_escrow::cancel_timelocks(
        env,
        accounts.external,
        contracts.card_escrow,
        true,
        true
    );
}

#[test(should_fail_with = "Assertion failed: Unauthorized: not card operator!")]
unconstrained fn test_cannot_spend_not_operator_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // deposit funds to escrow
    card_escrow::deposit(
       env,
       accounts.user,
       contracts.card_escrow,
       contracts.usdc,
       USDC_MINT_AMOUNT,
       false // no malicious authwit
    );

    // try to spend from non-operator account
    let epoch = card_escrow::compute_epoch();
    card_escrow::spend(
        env,
        accounts.external,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );
}