use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT},
        token::expect_private_balance
    }
};
use aztec::{
    oracle::execution::get_block_number,
    test::helpers::cheatcodes
};

/**
 * General happy path test case
 */
#[test]
unconstrained fn test_e2e() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // check config
    let config = card_escrow::get_config(contracts.card_escrow);
    assert_eq(config.owner, contracts.card_escrow, "Config owner mismatch!");
    assert_eq(config.token_address, contracts.usdc, "Config token address mismatch!");
    assert_eq(config.operator_address, accounts.operator, "Config operator address mismatch!");
    assert_eq(config.user_address, accounts.user, "Config user address mismatch!");
    assert_eq(config.spend_limit, INITIAL_SPEND_LIMIT, "Config spend limit mismatch!");

    // deposit to escrow
    card_escrow::deposit(
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
    let mut epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2,
        epoch,
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT / 2));
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT / 2);
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT / 2,
        epoch,
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - INITIAL_SPEND_LIMIT);
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT);

    // advance epoch
    cheatcodes::advance_timestamp_by(CardEscrow::EPOCH_LENGTH);
    assert(card_escrow::compute_epoch() == epoch + 1, "Epoch should have advanced by 1");
    epoch = epoch + 1;
    // spend from escrow in new epoch
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2));
    expect_private_balance(contracts.usdc, accounts.operator, INITIAL_SPEND_LIMIT * 2);

    // withdraw from escrow
    card_escrow::prepare_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2)
    );
    // advance past timelock 
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);
    card_escrow::withdraw(
        env,
        accounts.user,
        contracts.card_escrow,
        0
    );
    expect_private_balance(contracts.usdc, contracts.card_escrow, 0);
    expect_private_balance(contracts.usdc, accounts.user, USDC_MINT_AMOUNT - (INITIAL_SPEND_LIMIT * 2));
}

// Tests for a card operator attempting to overspend the limit in one transaction
// Tests spend_first_in_epoch and validates initial spent amount epoch note creation
#[test(should_fail_with = "Assertion failed: Spend limit exceeded!")]
unconstrained fn test_overspend_limit_1_tx_fail() {
    ///
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

// Tests for a card operator attempting to overspend the epoch spend limit in multiple transactions
// Tests spend_subsequent_in_epoch and validates read/update of spent amount epoch note
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

// Tests that revising the spending limit higher allows the card operator to spend more
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

// Tests that revising the spending limit lower prevents the card operator from spending the old limit
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

// tests that a operator can spend (up to the limit) while a withdraw is pending
// also tests that a user can withdraw the difference spent from pending withdraw
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

// tests that a operator can spend the old limit while a new, lower limit is pending
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

// tests that a user cannot withdraw more than they scheduled to withdraw
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

// test that an operator cannot spend more than available even if the limit allows for it
#[test(should_fail_with = "Assertion failed: Balance too low")]
unconstrained fn test_spend_more_than_available_fail() {
     // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // deposit to escrow
    card_escrow::deposit(
        env,
        accounts.user,
        contracts.card_escrow,
        contracts.usdc,
        INITIAL_SPEND_LIMIT + 1,
        false // no malicious authwit
    );

    // spend up to the limit for this epoch
    let mut epoch = card_escrow::compute_epoch();
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );

    // advance epoch
    cheatcodes::advance_timestamp_by(CardEscrow::EPOCH_LENGTH);
    
    // try to spend the limit again
    epoch = epoch + 1;
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
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

// test that the operator cannot use the wrong epoch when spending
#[test(should_fail_with = "Assertion failed: Epoch mismatch!")]
unconstrained fn test_cannot_spend_wrong_epoch() {
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

    // try to spend from a future epoch
    let epoch = card_escrow::compute_epoch() + 1;
    card_escrow::spend_from_escrow(
        env,
        accounts.operator,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );
}

// test that user cannot withdraw before timelock is over
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

// can update spending limit before timelock is over
#[test(should_fail_with = "Assertion failed: Spend limit timelock not elapsed!")]
unconstrained fn test_cannot_change_spending_limit_during_timelock_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
   
    // change spend limit
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );
    // advance to block before timelock is over
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS - 2);
    // try to finalize spend limit change
    card_escrow::finalize_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );
}

// test that cannot finalize a withdrawal without first scheduling it
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

// test that cannot finalize a spend limit change without first scheduling it
#[test(should_fail_with = "Assertion failed: No spend limit change has been scheduled!")]
unconstrained fn test_cannot_finalize_spend_limit_change_without_prepare_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to finalize spend limit change without preparing a change
    card_escrow::finalize_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );
}

// test that a withdrawal and spend limit change can be cancelled
#[test]
unconstrained fn test_card_escrow_cancel_timelocks() {
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

    // schedule a withdrawal
    let start_block = get_block_number();
    card_escrow::prepare_withdrawal(
       env,
       accounts.user,
       contracts.card_escrow,
       USDC_MINT_AMOUNT
    );

    // schedule a spend limit change
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );

    // check the timelock values are set
    let timelocks_private = card_escrow::get_timelocks_private(contracts.card_escrow);
    assert(timelocks_private.proposed_withdraw_amount == USDC_MINT_AMOUNT);
    assert(timelocks_private.proposed_spend_limit == INITIAL_SPEND_LIMIT * 2);

    let timelocks_public = card_escrow::get_timelocks_public(contracts.card_escrow);
    assert(timelocks_public.withdraw_timelock == start_block);
    assert(timelocks_public.spend_limit_timelock == start_block + 1);
    
    // cancel both timelocks
    card_escrow::cancel_timelocks(
        env,
        accounts.user,
        contracts.card_escrow,
        true, // cancel spend limit change
        true  // cancel withdrawal
    ); 

    // check the timelock values are unset
    let timelocks_private = card_escrow::get_timelocks_private(contracts.card_escrow);
    assert(timelocks_private.proposed_withdraw_amount == 0);
    assert(timelocks_private.proposed_spend_limit == 0);

    let timelocks_public = card_escrow::get_timelocks_public(contracts.card_escrow);
    assert(timelocks_public.withdraw_timelock == 0);
    assert(timelocks_public.spend_limit_timelock == 0);
}

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
    card_escrow::change_spend_limit(
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
    card_escrow::change_spend_limit(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to finalize spend limit change from non-user account
    card_escrow::finalize_spend_limit_change(
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
    card_escrow::prepare_withdrawal(
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
    card_escrow::prepare_withdrawal(
        env,
        accounts.user,
        contracts.card_escrow,
        USDC_MINT_AMOUNT
    );

    // advance past timelock
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS);

    // try to withdraw from non-user account
    card_escrow::withdraw(
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
    card_escrow::spend_from_escrow(
        env,
        accounts.external,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT,
        epoch,
    );
}