use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct SpendLimitNote {
    owner: AztecAddress,
    amount: u128,
    randomness: Field,
}

impl SpendLimitNote {
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
