use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

/** Mutable note used to track the current spend limit of the escrow */
#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct SpendLimitNote {
    // required field for note - will always be the escrow contract itself
    owner: AztecAddress,
    // the current spend limit, decremented with each card transaction
    amount: u128,
    // required field for a note - blinding factor
    randomness: Field,
}

impl SpendLimitNote {
    /** Creates a new spend limit note */
    pub fn new(
        owner: AztecAddress,
        amount: u128,
    ) -> Self {
        SpendLimitNote {
            owner,
            amount,
            randomness: unsafe { random() },
        }
    }
}
