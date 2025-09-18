use aztec::macros::aztec;

pub mod types;
pub mod test;

#[aztec]
pub contract CardEscrow {
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, private, public, internal, utility, view},
            storage::storage
        },
        oracle::notes::check_nullifier_exists,
        prelude::{
            AztecAddress,
            PublicMutable,
            PrivateMutable,
            PrivateImmutable,
            Map
        },
        protocol_types::{
            storage::map::derive_storage_slot_in_map,
            constants::GENERATOR_INDEX__INITIALIZATION_NULLIFIER,
            hash::poseidon2_hash_with_separator,
            traits::ToField,
        },
        messages::logs::note::encode_and_encrypt_note,
    };
    use poseidon::poseidon2::Poseidon2;
    use token_contract::Token;
    use crate::types::{
        config_note::ConfigNote,
        escrow_nonce_note::EscrowNonceNote,
        spend_limit_note::SpendLimitNote,
        timelock::Timelock,
        timelocked_note::TimelockedNote,
        spent_amount_epoch_note::SpentAmountEpochNote,
    };

    pub global TIMELOCK_BLOCKS: u32 = 30; // number of blocks that must elapse for a timelock
    pub global EPOCH_LENGTH: u64 = 86400; // seconds in a day
    pub global WITHDRAW_SIG_SEPARATOR: Field = 1;
    pub global SPEND_LIMIT_SIG_SEPARATOR: Field = 2;

    #[storage]
    struct Storage<Context> {
        config: PrivateImmutable<ConfigNote, Context>,
        escrow_nonce: PrivateMutable<EscrowNonceNote, Context>,
        spend_limit: PrivateMutable<SpendLimitNote, Context>,
        timelocks: PublicMutable<Timelock, Context>,
        timelocks_private: PrivateMutable<TimelockedNote, Context>,
        spend_epoch: Map<Field, PrivateMutable<SpentAmountEpochNote, Context>, Context>,
    }

    ////////////////////////////////
    ////////// CONSTRUCTOR /////////
    ////////////////////////////////
    
    #[private]
    #[initializer]
    fn constructor(
        token_address: AztecAddress,
        operator_address: AztecAddress,
        operator_pubkey_x: Field,
        operator_pubkey_y: Field,
        spend_limit: u128
    ) {
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // Create config note
        let config = ConfigNote::new(
            self_address,
            token_address,
            caller,
            operator_address,
            operator_pubkey_x,
            operator_pubkey_y,
        );
        storage.config.initialize(config).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // Initialize empty escrow nonce note
        let escrow_nonce_note = EscrowNonceNote::new(self_address, 1);
        storage.escrow_nonce.initialize(escrow_nonce_note).emit(encode_and_encrypt_note
            (&mut context,
            self_address,
            self_address
        ));

        // Initialize spend limit note
        let spend_limit_note = SpendLimitNote::new(self_address, spend_limit);
        storage.spend_limit.initialize(spend_limit_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
        

        // Initialize empty timelock notes
        let timelocked_note = TimelockedNote::new(self_address, 0, 0);
        storage.timelocks_private.initialize(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
    }
    
    /////////////////////////////
    ////////// PRIVATE //////////
    /////////////////////////////

    ////////// DEPOSIT //////////

    #[private]
    fn deposit(amount: u128, _nonce: Field) {
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // transfer tokens in
        Token::at(config.token_address)
            .transfer_private_to_private(
                caller,
                self_address,
                amount,
                _nonce
            )
            .call(&mut context);
    }
    
    ////////// SPEND //////////

    #[private]
    fn spend(amount: u128, epoch: Field) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.operator_address == caller, "Unauthorized: not card operator!");
        
        // check epoch note has been initialized and create/ update it
        let is_initialized = unsafe { _check_spend_epoch_initialized(epoch) };
        let mut spend_amount_epoch_note = SpentAmountEpochNote::new(
            context.this_address(),
            amount,
        );
        if is_initialized {
            let existing_note = storage.spend_epoch.at(epoch).get_note().note;
            spend_amount_epoch_note.spent_amount += existing_note.spent_amount;
        }

        // get spend limit note
        let spend_limit_note = _get_spend_limit_and_reemit(&mut context, storage.spend_limit);

        // check the spend amount against the limit
        assert(
            spend_limit_note.amount >= spend_amount_epoch_note.spent_amount,
            "Spend limit exceeded!"
        );

        // store the note
        storage
            .spend_epoch
            .at(epoch)
            .initialize_or_replace(spend_amount_epoch_note)
            .emit(encode_and_encrypt_note(
                &mut context,
                context.this_address(),
                context.this_address()
            ));

        // transfer the tokens out
        Token::at(config.token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                amount,
                0
            )
            .call(&mut context);
        // enqueue a check to make sure the asserted epoch is correct
        CardEscrow::at(self_address)
            .check_epoch(epoch)
            .enqueue(&mut context);

        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    ////////// WITHDRAW //////////

    #[private]
    fn withdraw(amount: u128, signature: [u8; 64]) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // get the escrow nonce
        let mut escrow_nonce_note = storage.escrow_nonce.get_note().note;

        // authenticate the signature
        let preimage = [
            context.this_address().to_field(),
            amount as Field,
            escrow_nonce_note.nonce,
            WITHDRAW_SIG_SEPARATOR
        ];
        let payload: [u8; 32] = Poseidon2::hash(preimage, 4).to_le_bytes();
        schnorr::verify_signature(
            config.operator_schnorr_pubkey(),
            signature,
            payload
        );

        // check no pending spend limit change or withdrawal
        let timelock_note_emission = storage.timelocks_private.get_note();
        timelock_note_emission.emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
        assert(
            (timelock_note_emission.note.proposed_spend_limit == 0)
            & (timelock_note_emission.note.proposed_withdraw_amount == 0),
            "Cannot change spend limit by signature while any timelock is active!"
        );

        // bump the escrow nonce
        escrow_nonce_note.nonce += 1;
        storage.escrow_nonce.replace(escrow_nonce_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // transfer tokens out unilaterally
        Token::at(config.token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                amount,
                0
            )
            .call(&mut context);
        
        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    #[private]
    fn prepare_forced_withdrawal(amount: u128) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // update the timelock in mutable config
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        timelocked_note.proposed_withdraw_amount = amount;
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // publicly enqueue the timelock
        CardEscrow::at(self_address)
            ._set_timelock(false, true)
            .enqueue(&mut context);

        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    #[private]
    fn finalize_forced_withdrawal(amount: u128) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // get the amount to transfer from the timelocked note
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        let mut amount_to_withdraw = timelocked_note.proposed_withdraw_amount;

        // check there is a pending withdrawal
        // NOTE: should we remove this? all you can do is withdraw 0...
        assert(amount_to_withdraw != 0, "No withdrawal has been scheduled!");

        // handle withdrawing less than timelocked amount
        if amount > 0 {
            assert(
                amount <= amount_to_withdraw,
                "Requested withdraw amount exceeds proposed withdraw amount!"
            );
            amount_to_withdraw = amount;
        }

        // reset the timelock note
        timelocked_note.proposed_withdraw_amount = 0;
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // transfer the tokens out
        Token::at(config.token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                amount_to_withdraw,
                0
            )
            .call(&mut context);

        // enqueue public check that timelock is elapsed
        CardEscrow::at(self_address)
            ._elapse_timelock(false, true)
            .enqueue(&mut context);

        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    ////////// SPEND LIMIT //////////

    #[private]
    fn change_spend_limit(
        new_spend_limit: u128,
        signature: [u8; 64]
    ) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card operator!");

        // get the escrow nonce
        let mut escrow_nonce_note = storage.escrow_nonce.get_note().note;

        // authenticate the signature
        let preimage = [
            context.this_address().to_field(),
            new_spend_limit as Field,
            escrow_nonce_note.nonce,
            SPEND_LIMIT_SIG_SEPARATOR
        ];
        let payload: [u8; 32] = Poseidon2::hash(preimage, 4).to_le_bytes();
        schnorr::verify_signature(
            config.operator_schnorr_pubkey(),
            signature,
            payload
        );

        // bump the escrow nonce
        escrow_nonce_note.nonce += 1;
        storage.escrow_nonce.replace(escrow_nonce_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // check no pending spend limit change or withdrawal
        let timelock_note_emission = storage.timelocks_private.get_note();
        timelock_note_emission.emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
        assert(
            (timelock_note_emission.note.proposed_spend_limit == 0)
            & (timelock_note_emission.note.proposed_withdraw_amount == 0),
            "Cannot change spend limit by signature while any timelock is active!"
        );

        // update the spend limit unilaterally
        let mut spend_limit_note = storage.spend_limit.get_note().note;
        spend_limit_note.amount = new_spend_limit;
        storage.spend_limit.replace(spend_limit_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    #[private]
    fn prepare_forced_spend_limit_change(new_spend_limit: u128) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // update the timelocked note
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        timelocked_note.proposed_spend_limit = new_spend_limit;
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // publicly enqueue the timelock
        CardEscrow::at(self_address)
            ._set_timelock(true, false)
            .enqueue(&mut context);
    }

    #[private]
    fn finalize_forced_spend_limit_change() {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(
            (config.user_address == caller)
            | (config.operator_address == caller),
            "Unauthorized: not card user or operator!"
        );

        // check that a spend limit change has been scheduled
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        let proposed_spend_limit = timelocked_note.proposed_spend_limit;
        assert(proposed_spend_limit != 0, "No spend limit change has been scheduled!");

        // get mutable config to update
        let mut spend_limit_note = storage.spend_limit.get_note().note;

        // update the spend limit
        spend_limit_note.amount = timelocked_note.proposed_spend_limit;
        storage.spend_limit.replace(spend_limit_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // reset the timelock note
        timelocked_note.proposed_spend_limit = 0;
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // enqueue public check that timelock is elapsed
        CardEscrow::at(self_address)
            ._elapse_timelock(true, false)
            .enqueue(&mut context);
    }

    ////////// TIMELOCKS //////////

    #[private]
    fn cancel_timelocks(spend_limit: bool, withdraw: bool) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note();
        assert(config.user_address == caller, "Unauthorized: not card user!");

        // reset the timelock note
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        if spend_limit {
            timelocked_note.proposed_spend_limit = 0;
        }
        if withdraw {
            timelocked_note.proposed_withdraw_amount = 0;
        }
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // reset the public timelock
        CardEscrow::at(self_address)
            ._cancel_timelock(spend_limit, withdraw)
            .enqueue(&mut context);

        // bump nonce to invalidate any pending signatures
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    ////////// NONCE //////////

    #[private]
    fn bump_nonce() {
        let self_address = context.this_address();
        let caller = context.msg_sender();
        // authorize this call
        let config = storage.config.get_note();
        assert(config.operator_address == caller, "Unauthorized: not card user!");

        // bump the nonce
        _bump_nonce(&mut context, storage.escrow_nonce, self_address);
    }

    ////////////////////////////
    ////////// PUBLIC //////////
    ////////////////////////////

    #[public]
    #[internal]
    fn _set_timelock(spend_limit: bool, withdraw: bool) {
        let mut timelock = storage.timelocks.read();
        let current_block = context.block_number();
        if spend_limit {
            assert(timelock.spend_limit_timelock == 0, "Spend limit timelock already exists!");
            timelock.spend_limit_timelock = current_block;
        }
        if withdraw {
            assert(timelock.withdraw_timelock == 0, "Withdraw timelock already exists!");
            timelock.withdraw_timelock = current_block;
        }
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn _elapse_timelock(spend_limit: bool, withdraw: bool) {
        let mut timelock = storage.timelocks.read();
        let current_block = context.block_number();
        if spend_limit {
            assert(
                timelock.spend_limit_timelock + TIMELOCK_BLOCKS <= current_block,
                "Spend limit timelock not elapsed!"
            );
            timelock.withdraw_timelock = 0;
        }
        if withdraw {
            assert(
                timelock.withdraw_timelock + TIMELOCK_BLOCKS <= current_block,
                "Withdraw timelock not elapsed!"
            );
            timelock.withdraw_timelock = 0;
        }
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn _cancel_timelock(spend_limit: bool, withdraw: bool) {
        let mut timelock = storage.timelocks.read();
        if spend_limit {
            timelock.spend_limit_timelock = 0;
        }
        if withdraw {
            timelock.withdraw_timelock = 0;
        }
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn check_epoch(asserted_epoch: Field) {
        let timestamp = context.timestamp();
        let current_epoch = (timestamp / EPOCH_LENGTH) as Field;
        assert(current_epoch == asserted_epoch, "Epoch mismatch!");
    }
    

    #[public]
    #[view]
    fn get_timelocks_public() -> Timelock {
        storage.timelocks.read()
    }

    ////////////////////////////
    ///////// LIBRARY //////////
    ////////////////////////////

    #[contract_library_method]
    fn _get_spend_limit_and_reemit(
        context: &mut PrivateContext,
        spend_limit_storage: PrivateMutable<SpendLimitNote, &mut PrivateContext>
    ) -> SpendLimitNote {
        let self_address = context.this_address();
        let emission = spend_limit_storage.get_note();
        emission.emit(encode_and_encrypt_note(
            context,
            self_address,
            self_address
        ));
        emission.note
    }

    #[contract_library_method]
    unconstrained fn _check_spend_epoch_initialized(
        epoch: Field
    ) -> bool {
        // get the slot the spent amount epoch note would be stored at
        let map_slot = CardEscrow::storage_layout().spend_epoch.slot;
        let epoch_slot = derive_storage_slot_in_map(map_slot, epoch);
        // compute the initialization nullifier
        let nullifier = poseidon2_hash_with_separator(
            [epoch_slot],
            GENERATOR_INDEX__INITIALIZATION_NULLIFIER,
        );
        // check with oracle call if it exists and return
        unsafe { check_nullifier_exists(nullifier) }
    }

    #[contract_library_method]
    fn _bump_nonce(
        context: &mut PrivateContext,
        escrow_nonce_storage: PrivateMutable<EscrowNonceNote, &mut PrivateContext>,
        self_address: AztecAddress,
    ) {
        let mut escrow_nonce_note = escrow_nonce_storage.get_note().note;
        escrow_nonce_note.nonce += 1;
        escrow_nonce_storage.replace(escrow_nonce_note).emit(encode_and_encrypt_note(
            context,
            self_address,
            self_address
        ));
    }

    ////////////////////////////
    ///////// UTILITY //////////
    ////////////////////////////

    #[utility]
    pub unconstrained fn get_nonce() -> Field {
        storage.escrow_nonce.view_note().nonce
    }

    #[utility]
    pub unconstrained fn get_config() -> ConfigNote {
        storage.config.view_note()
    }

    #[utility]
    pub unconstrained fn get_spend_limit() -> u128 {
        let spend_limit_note = storage.spend_limit.view_note();
        spend_limit_note.amount
    }

    #[utility]
    pub unconstrained fn get_timelocks_private() -> TimelockedNote {
        storage.timelocks_private.view_note()
    }
}
