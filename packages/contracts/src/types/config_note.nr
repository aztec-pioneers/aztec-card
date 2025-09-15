use aztec::{
    macros::notes::note,
    oracle::random::random,
    prelude::AztecAddress,
    protocol_types::traits::{Deserialize, Serialize},
};

#[note]
#[derive(Eq, Serialize, Deserialize)]
pub struct ConfigNote {
    owner: AztecAddress,
    token_address: AztecAddress,
    operator_address: AztecAddress,
    user_address: AztecAddress,
    spend_limit: u128,
    randomness: Field,
}

impl ConfigNote {
    pub fn new(
        owner: AztecAddress,
        token_address: AztecAddress,
        operator_address: AztecAddress,
        user_address: AztecAddress,
        spend_limit: u128,
    ) -> Self {
        ConfigNote {
            owner,
            token_address,
            operator_address,
            user_address,
            spend_limit,
            randomness: unsafe { random() },
        }
    }
}
