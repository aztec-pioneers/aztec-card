use aztec::{
    oracle::{
        random::random,
        execution::{get_contract_address, get_timestamp}
    },
    prelude::AztecAddress,
    protocol_types::contract_instance::ContractInstance,
    test::helpers::{
        test_environment::TestEnvironment,
        cheatcodes,
        authwit as authwit_cheatcodes
    }
};
use crate::{
    CardEscrow,
    types::config_note::ConfigNote,
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

pub unconstrained fn deposit_to_escrow(
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
    card_escrow_address: AztecAddress
) {
    env.impersonate(user_address);
    CardEscrow::at(card_escrow_address)
        .withdraw()
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
    operator_address: AztecAddress,
    card_escrow_address: AztecAddress
) {
    env.impersonate(operator_address);
    CardEscrow::at(card_escrow_address)
        .finalize_spend_limit_change()
        .call(&mut env.private());
    env.advance_block_by(1);
}
