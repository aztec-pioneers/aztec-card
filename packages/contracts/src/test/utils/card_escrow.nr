use aztec::{
    oracle::{
        random::random,
        execution::{get_contract_address, get_timestamp, get_block_number},
        storage::storage_read,
    },
    prelude::AztecAddress,
    test::helpers::{
        test_environment::TestEnvironment,
        cheatcodes,
    }
};
use crate::{
    CardEscrow,
    types::{
        config_note::ConfigNote,
        timelock::Timelock,
        timelocked_note::TimelockedNote
    },
    test::utils::token::{private_transfer_authwit, mint_to_private}
};

pub unconstrained fn get_config(
    escrow_address: AztecAddress
) -> ConfigNote {
    // set cheatcode address to escrow
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(escrow_address);

    // read definition
    let definition = CardEscrow::get_config();

    // set cheatcode address back to original
    cheatcodes::set_contract_address(current_contract_address);

    definition
}

pub unconstrained fn compute_epoch() -> Field {
    get_timestamp() as Field / 86400
}

pub unconstrained fn deposit(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress,
    token_address: AztecAddress,
    amount: u128,
    malicious_authwit: bool
) {
    // add transfer authwit
    let mut nonce = unsafe { random() };
    private_transfer_authwit(
        token_address,
        card_escrow_address,
        user_address,
        amount,
        nonce
    );
    
    // increment nonce to make authwit invalid
    if malicious_authwit {
        nonce = nonce + 1;
    }

    // call deposit
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .deposit(amount, nonce)
        .call(&mut env.private());
    
    // advance block
    env.advance_block_by(1);
}

pub unconstrained fn spend_from_escrow(
    env: &mut TestEnvironment,
    operator_address: AztecAddress,
    card_escrow_address: AztecAddress,
    amount: u128,
    epoch: Field,
    first_in_epoch: bool
) {
    env.impersonate(operator_address);
    if first_in_epoch {
        CardEscrow::at(card_escrow_address)
            .spend_first_in_epoch(amount, epoch)
            .call(&mut env.private());
    } else {
        CardEscrow::at(card_escrow_address)
            .spend_subsequent_in_epoch(amount, epoch)
            .call(&mut env.private());
    }
    env.advance_block_by(1);
}

pub unconstrained fn prepare_withdrawal(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress,
    amount: u128
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .prepare_withdrawal(amount)
        .call(&mut env.private());
    env.advance_block_by(1);
}

pub unconstrained fn withdraw(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress,
    amount: u128
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .withdraw(amount)
        .call(&mut env.private());
    env.advance_block_by(1);
}

pub unconstrained fn change_spend_limit(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress,
    new_spend_limit: u128
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .change_spend_limit(new_spend_limit)
        .call(&mut env.private());
    env.advance_block_by(1);
}

pub unconstrained fn finalize_spend_limit_change(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .finalize_spend_limit_change()
        .call(&mut env.private());
    env.advance_block_by(1);
}

pub unconstrained fn cancel_timelocks(
    env: &mut TestEnvironment,
    user_address: AztecAddress,
    card_escrow_address: AztecAddress,
    cancel_spend_limit: bool,
    cancel_withdrawal: bool
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .cancel_timelocks(cancel_spend_limit, cancel_withdrawal)
        .call(&mut env.private());
    env.advance_block_by(1);
}


pub unconstrained fn get_timelocks_private(
    card_escrow_address: AztecAddress
) -> TimelockedNote {
    // set cheatcode address to escrow
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(card_escrow_address);

    // read definition
    let timelocked_note = CardEscrow::get_timelocks_private();

    // set cheatcode address back to original
    cheatcodes::set_contract_address(current_contract_address);

    timelocked_note
}

pub unconstrained fn get_timelocks_public(
    card_escrow_address: AztecAddress,
) -> Timelock {
    let current_contract_address = get_contract_address();
    cheatcodes::set_contract_address(card_escrow_address);
    let block_number = get_block_number();

    let timelocks_slot = CardEscrow::storage_layout().timelocks.slot;
    let timelock: Timelock = storage_read(card_escrow_address, timelocks_slot, block_number);
    cheatcodes::set_contract_address(current_contract_address);
    timelock
}