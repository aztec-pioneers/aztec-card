pub(crate) mod authorization;
pub(crate) mod epoch_validation;
pub(crate) mod spend_limits;
pub(crate) mod timelock_management;
pub(crate) mod withdrawals;

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
unconstrained fn test_e2e() {
    // get test environment
    let (env, accounts, contracts) = setup(true);
    
    // check config
    let config = card_escrow::get_config(contracts.card_escrow);
    assert_eq(config.owner, contracts.card_escrow, "Config owner mismatch!");
    assert_eq(config.token_address, contracts.usdc, "Config token address mismatch!");
    assert_eq(config.operator_address, accounts.operator, "Config operator address mismatch!");
    assert_eq(config.user_address, accounts.user, "Config user address mismatch!");
    // check spend limit
    let spend_limit = card_escrow::get_spend_limit(contracts.card_escrow);
    assert_eq(spend_limit, INITIAL_SPEND_LIMIT, "Config spend limit mismatch!");

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