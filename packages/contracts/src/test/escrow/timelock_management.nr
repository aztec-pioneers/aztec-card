use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT}
    }
};
use aztec::{
    oracle::execution::get_block_number,
    test::helpers::cheatcodes
};

#[test(should_fail_with = "Assertion failed: Spend limit timelock not elapsed!")]
unconstrained fn test_cannot_change_spending_limit_during_timelock_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
   
    // change spend limit
    card_escrow::prepare_forced_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow,
        INITIAL_SPEND_LIMIT * 2
    );
    // advance to block before timelock is over
    cheatcodes::advance_blocks_by(CardEscrow::TIMELOCK_BLOCKS - 2);
    // try to finalize spend limit change
    card_escrow::finalize_forced_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );
}

#[test(should_fail_with = "Assertion failed: No spend limit change has been scheduled!")]
unconstrained fn test_cannot_finalize_spend_limit_change_without_prepare_fail() {
    // get test environment
    let (env, accounts, contracts) = setup(true);

    // try to finalize spend limit change without preparing a change
    card_escrow::finalize_forced_spend_limit_change(
        env,
        accounts.user,
        contracts.card_escrow
    );
}

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
    card_escrow::prepare_forced_withdrawal(
       env,
       accounts.user,
       contracts.card_escrow,
       USDC_MINT_AMOUNT
    );

    // schedule a spend limit change
    card_escrow::prepare_forced_spend_limit_change(
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