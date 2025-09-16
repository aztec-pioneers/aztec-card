use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT},
        token::expect_private_balance
    }
};
use aztec::test::helpers::cheatcodes;

#[test]
unconstrained fn test_spend_with_pending_withdraw() {
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

    // attempt a withdraw of the full amount
    card_escrow::prepare_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT
    );
    // spend up to the limit
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

    // withdraw the difference
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT - INITIAL_SPEND_LIMIT
    );

    // check expected balances
    expect_private_balance(contracts.usdc, contracts.card_escrow, 0);
    expect_private_balance(contracts.usdc, accounts.user, USDC_MINT_AMOUNT - INITIAL_SPEND_LIMIT);
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT);
}

#[test(should_fail_with = "Assertion failed: Requested withdraw amount exceeds proposed withdraw amount")]
unconstrained fn test_withdraw_more_than_scheduled_fail() {
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

    // attempt a withdraw of half the amount
    card_escrow::prepare_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT / 2
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to withdraw the 1 unit more than requested
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        (USDC_MINT_AMOUNT / 2) + 1
    );
}

#[test(should_fail_with = "Assertion failed: Balance too low")]
unconstrained fn test_cannot_withdraw_more_than_available_fail() {
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

    // attempt a withdraw of more than available
    // NOTE: there is no way to constrain the balance of the token privately without a state proof
    //       just not worth it when it eventually is caught by transfer anyways
    card_escrow::prepare_withdrawal(
       env,
       accounts.user,
       contracts.card_escrow,
       USDC_MINT_AMOUNT + 1
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to withdraw the full amount
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        0
    );
}

#[test(should_fail_with = "Assertion failed: Withdraw timelock not elapsed!")]
unconstrained fn test_cannot_withdraw_during_timelock_fail() {
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

    // prepare a withdrawal
    card_escrow::prepare_withdrawal(
       env,
       accounts.user,
       contracts.card_escrow,
       USDC_MINT_AMOUNT
    );
    // advance to block before timelock is over
    // NOTE: -2 because we increment the block after the withdrawal call
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS - 2);
    // try to withdraw
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        0
    );
}

#[test(should_fail_with = "Assertion failed: No withdrawal has been scheduled!")]
unconstrained fn test_cannot_finalize_withdraw_without_prepare_fail() {
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

    // try to withdraw without preparing a withdrawal
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        0
    );
}