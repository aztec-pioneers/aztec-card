use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

/** Mutable note used to track proposed spend limit and withdraw amounts subject to timelocks */
#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct TimelockedNote {
    // required field for note - will always be the escrow contract itself
    owner: AztecAddress,
    // the proposed spend limit to be set
    proposed_spend_limit: u128,
    // the proposed maximum amount the user can withdraw
    proposed_withdraw_amount: u128,
    // required field for a note - blinding factor
    randomness: Field,
}

impl TimelockedNote {
    /** Creates a new timelocked note */
    pub fn new(
        owner: AztecAddress,
        proposed_spend_limit: u128,
        proposed_withdraw_amount: u128,
    ) -> Self {
        TimelockedNote {
            owner,
            proposed_spend_limit,
            proposed_withdraw_amount,
            randomness: unsafe { random() },
        }
    }
}