use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct TimelockedNote {
    owner: AztecAddress,
    proposed_spend_limit: u128,
    proposed_withdraw_amount: u128,
    randomness: Field,
}

impl TimelockedNote {
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