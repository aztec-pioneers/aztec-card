# User Withdrawals from the Card Escrow
Withdrawals from the escrow is a potentially contentious action that can negatively impact the card operator if used maliciously. There are two API's available:
* Forced/ timelocked withdrawals (using `prepare_forced_withdrawal()` and `finalize_forced_withdrawal()`), documented in the [timelock docs](./timelocks.md)
* Signed withdrawals (using `withdraw()`) documented in the [signed operations docs](./signed_operations.md).

Diagrams for the general flow and explanations of how these operations occur are included in the docs linked above.

Withdrawing at its core is really a simple operation - it is a `Token::transfer_private_to_private()` of some amount from the escrow contract to the user address. Almost all additional logic is either authentication of the caller, bumping nonces, or the timelocked/ signed flows for confirming a withdrawal - all of which has been documented elsewhere and does not need redundant explanation of.

## Timelocked Withdrawals After Spends
Take the case where:
 * An escrow has 10 tokens and a spend limit of 10 tokens
 * A user prepares a withdrawal of 10 tokens
 * The operator makes a spend of 5 tokens

The `finalize_forced_withdrawal(amount)` function includes an amount as a parameter to handle this case. This function will of course check that the provided `amount` does not exceed the `proposed_withdrawal_amount` in the `TimelockedNote`. However, it will allow the user to withdraw any amount up to `proposed_withdrawal_amount`. In this case, the user can call `finalize_forced_withdrawal(5)` to withdraw the remaining balance after `spend(5, {epoch})` was called.