use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

/** Mutable note used to track the amount spent in the current epoch */
#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct SpentAmountEpochNote {
    // required field for note - will always be the escrow contract itself
    owner: AztecAddress,
    // the amount spent in the current epoch, starts at 0 at the start of each epoch
    spent_amount: u128,
    // required field for a note - blinding factor
    randomness: Field,
}

impl SpentAmountEpochNote {
    /** Creates a new spent amount epoch note */
    pub fn new(
        owner: AztecAddress,
        spent_amount: u128
    ) -> Self {
        SpentAmountEpochNote {
            owner,
            spent_amount,
            randomness: unsafe { random() },
        }
    }
}
