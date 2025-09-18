export const TOKEN_METADATA = {
    usdc: { name: "USD Coin", symbol: "USDC", decimals: 6 },
}

export type SIGNED_ACTION_TYPE = "spendLimit" | "withdraw";

export const SEPARATOR = {
    spendLimit: 1n,
    withdraw: 2n,
}