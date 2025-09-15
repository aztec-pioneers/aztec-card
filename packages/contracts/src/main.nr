use aztec::macros::aztec;

pub mod types;
pub mod test;

#[aztec]
pub contract CardEscrow {
    // aztec library imports
    use aztec::{
        context::PrivateContext,
        macros::{
            functions::{initializer, private, public, internal, utility},
            storage::storage
        },
        prelude::{
            AztecAddress,
            PublicMutable,
            PrivateMutable,
            Map
        },
        messages::logs::note::encode_and_encrypt_note,
        protocol_types::traits::ToField,
    };
    use token_contract::Token;
    use crate::types::{
        config_note::ConfigNote,
        timelock::Timelock,
        timelocked_note::TimelockedNote,
        spent_amount_epoch_note::SpentAmountEpochNote,
    };

    // number of blocks that must elapse for a timelock
    global TIMELOCK_BLOCKS: u32 = 30;

    #[storage]
    struct Storage<Context> {
        config: PrivateMutable<ConfigNote, Context>,
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
        spend_limit: u128
    ) {
        let self_address = context.this_address();
        let caller = context.msg_sender();

        // Create config note
        let config = ConfigNote::new(
            self_address,
            token_address,
            operator_address,
            caller,
            spend_limit
        );
        storage.config.initialize(config).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));
        // initialize the timelock note
        let timelocked_note = TimelockedNote::new(self_address, 0, 0);
        storage.timelocks_private.initialize(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

    }
    
    ////////////////////////////
    ////////// PRIVATE /////////
    ////////////////////////////

    #[private]
    fn deposit(amount: u128, _nonce: Field) {
        let config = storage.config.get_note().note;
        let self_address = context.this_address();
        let caller = context.msg_sender();

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

    #[private]
    fn prepare_withdrawal(amount: u128) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note().note;
        assert(config.user_address == caller, "Unauthorized: not card user");

        // update the timelocked note
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        timelocked_note.proposed_withdraw_amount = amount;
        storage.timelocks_private.replace(timelocked_note).emit(encode_and_encrypt_note(
            &mut context,
            self_address,
            self_address
        ));

        // publicly enqueue the timelock
        CardEscrow::at(self_address)
            .set_withdraw_timelock()
            .enqueue(&mut context);
    }

    #[private]
    fn withdraw() {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note().note;
        assert(config.user_address == caller, "Unauthorized: not card user");

        // get the amount to transfer from the timelocked note
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        let amount = timelocked_note.proposed_withdraw_amount;

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
                amount,
                0
            )
            .call(&mut context);

        // enqueue public check that timelock is elapsed
        CardEscrow::at(self_address)
            .elapse_withdraw_timelock()
            .enqueue(&mut context);
    }


    // separate because we can't read a note if it doesnt exist
    // will fail when initialize is called if not the first note
    #[private]
    fn spend_first_in_epoch(amount: u128, epoch: Field) {
        // common spend logic
        let config = storage.config.get_note().note;
        let spending_limit = _spend(&mut context, config, amount, epoch);

        // check the spend amount agains the limit
        assert(spending_limit >= amount, "Spend limit exceeded!");

        // create the spent amount epoch note
        let spent_amount_epoch_note = SpentAmountEpochNote::new(
            context.this_address(),
            amount,
        );
        storage
            .spend_epoch
            .at(epoch)
            .initialize(spent_amount_epoch_note)
            .emit(encode_and_encrypt_note(
                &mut context,
                context.this_address(),
                context.this_address()
            ));
    }

    #[private]
    fn spend_subsequent_in_epoch(amount: u128, epoch: Field) {
        // common spend logic
        let config = storage.config.get_note().note;
        let spending_limit = _spend(&mut context, config, amount, epoch);

        // get the existing epoch note
        let mut spent_amount_epoch_note = storage
            .spend_epoch
            .at(epoch)
            .get_note()
            .note;

        // check the spend amount against the limit
        let new_spent_amount = spent_amount_epoch_note.spent_amount + amount;
        assert(spending_limit >= new_spent_amount, "Spend limit exceeded!");

        // update the spent amount epoch note
        spent_amount_epoch_note.spent_amount = new_spent_amount;
        storage
            .spend_epoch
            .at(epoch)
            .replace(spent_amount_epoch_note)
            .emit(encode_and_encrypt_note(
                &mut context,
                context.this_address(),
                context.this_address()
            ));
    }

    // todo: we should make this a delayed public mutable so that we can change it in one tx?

    #[private]
    fn change_spend_limit(new_spend_limit: u128) {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let config = storage.config.get_note().note;
        assert(config.user_address == caller, "Unauthorized: not card user");

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
            .set_spend_limit_timelock()
            .enqueue(&mut context);
    }

    #[private]
    fn finalize_spend_limit_change() {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        let mut config = storage.config.get_note().note;
        assert(config.user_address == caller, "Unauthorized: not card user");

        // update the spend limit
        let mut timelocked_note = storage.timelocks_private.get_note().note;
        config.spend_limit = timelocked_note.proposed_spend_limit;
        storage.config.replace(config).emit(encode_and_encrypt_note(
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
            .elapse_spend_limit_timelock()
            .enqueue(&mut context);
    }

    ////////////////////////////
    ////////// PUBLIC //////////
    ////////////////////////////

    #[public]
    #[internal]
    fn set_spend_limit_timelock() {
        // check the timelock is 0
        let mut timelock = storage.timelocks.read();
        assert(timelock.spend_limit_timelock == 0, "Spend limit timelock already exists!");
        // set block number
        timelock.spend_limit_timelock = context.block_number();
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn set_withdraw_timelock() {
        // check the timelock is 0
        let mut timelock = storage.timelocks.read();
        assert(timelock.withdraw_timelock == 0, "Withdraw timelock already exists!");
        // set block number
        timelock.withdraw_timelock = context.block_number();
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn elapse_spend_limit_timelock() {
        // check the timelock has elapsed
        let mut timelock = storage.timelocks.read();
        let current_block = context.block_number();
        assert(
            timelock.spend_limit_timelock + TIMELOCK_BLOCKS <= current_block,
            "Spend limit timelock not elapsed!"
        );
        // reset the timelock
        timelock.spend_limit_timelock = 0;
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn elapse_withdraw_timelock() {
        // check the timelock has elapsed
        let mut timelock = storage.timelocks.read();
        let current_block = context.block_number();
        assert(
            timelock.withdraw_timelock + TIMELOCK_BLOCKS <= current_block,
            "Withdraw timelock not elapsed!"
        );
        // reset the timelock
        timelock.withdraw_timelock = 0;
        storage.timelocks.write(timelock);
    }

    #[public]
    #[internal]
    fn check_epoch(asserted_epoch: Field) {
        let timestamp = context.timestamp();
        let current_epoch = (timestamp as Field / 86400) as Field;
        assert(current_epoch == asserted_epoch, "Epoch mismatch");
    }

    ////////////////////////////
    ///////// UTILITY //////////
    ////////////////////////////

    #[contract_library_method]
    fn _spend(
        context: &mut PrivateContext,
        config: ConfigNote,
        amount: u128,
        epoch: Field
    ) -> u128 {
        let caller = context.msg_sender();
        let self_address = context.this_address();

        // authorize this call
        assert(config.operator_address == caller, "Unauthorized: not card operator");


        // transfer the tokens out
        Token::at(config.token_address)
            .transfer_private_to_private(
                self_address,
                caller,
                amount,
                0
            )
            .call(context);

        // enqueue a check to make sure the asserted epoch is correct
        CardEscrow::at(self_address)
            .check_epoch(epoch)
            .enqueue(context);
        
        // return the spend cap
        config.spend_limit
    }

    #[utility]
    pub unconstrained fn get_config() -> ConfigNote {
        storage.config.view_note()
    }

}
