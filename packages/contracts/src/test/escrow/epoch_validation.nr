use crate::{
    CardEscrow,
    test::utils::{
        card_escrow,
        setup::{setup, USDC_MINT_AMOUNT, INITIAL_SPEND_LIMIT},
        token::expect_private_balance
    }
};
use aztec::test::helpers::cheatcodes;

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