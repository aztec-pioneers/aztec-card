import {
    AccountWallet,
    PXE,
    Fr,
    L1FeeJuicePortalManager,
    FeeJuicePaymentMethodWithClaim,
    Schnorr,
    GrumpkinScalar,
    Fq,
} from "@aztec/aztec.js";
import { CheatCodes } from "@aztec/aztec.js/testing"
import { getInitialTestAccountsManagers } from "@aztec/accounts/testing";
import {
    deployEscrowContract,
    deployTokenContractWithMinter,
    wad,
    depositToEscrow,
    createPXE,
    getFeeJuicePortalManager,
    TOKEN_METADATA,
    expectBalancePrivate,
    CardEscrowContract,
    TokenContract,
    setupAccountWithFeeClaim,
    createCheatCodes,
    buildSignedEscrowMessage
} from "../src";

export const computeEpoch = async (cc: CheatCodes): Promise<Fr> => {
    const timestamp = await cc.aztec.timestamp();
    return new Fr(Math.floor(timestamp / 86400));
}

describe("Private Transfer Demo Test", () => {
    let pxe: PXE;
    let cc: CheatCodes;

    let minter: AccountWallet;
    let user: AccountWallet;

    let operator: AccountWallet;

    let escrowMasterKey: Fr;

    let escrow: CardEscrowContract;
    let usdc: TokenContract;

    let operatorFeeJuicePortalManager: L1FeeJuicePortalManager;

    const INITIAL_SPEND_LIMIT = wad(1000n, 6n);
    const MINT_AMOUNT = wad(10000n, 6n);

    beforeAll(async () => {
        // setup PXE connections
        pxe = await createPXE();
        cc = await createCheatCodes(pxe);

        // get PXE 1 accounts
        const wallets = await Promise.all(
            (await getInitialTestAccountsManagers(pxe)).map(m => m.register())
        );
        minter = wallets[0];
        user = wallets[1];
        operator = wallets[2]

        // deploy token contract and mint
        usdc = await deployTokenContractWithMinter(TOKEN_METADATA.usdc, minter);
        await usdc
            .withWallet(minter)
            .methods.mint_to_private(
                minter.getAddress(),
                user.getAddress(),
                MINT_AMOUNT
            )
            .send()
            .wait();

    });

    test("e2e by signature", async () => {
        let signingKey = Fq.random();
        let schnorr = new Schnorr();
        const schnorrPubkey = await schnorr.computePublicKey(signingKey).then(p => p.toBigInts());

        ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
            pxe,
            user,
            usdc.address,
            operator.getAddress(),
            schnorrPubkey,
            INITIAL_SPEND_LIMIT
        ));

        //// change spend limit privately in one transaction
        const spendLimitChange = wad(2000n, 6n);

        // get nonce
        let nonce = await escrow.withWallet(operator).methods.get_nonce().simulate();
        
        const signature = await buildSignedEscrowMessage(
            signingKey,
            escrow.address,
            spendLimitChange,
            nonce,
            "spendLimit"
        ).then(sig => Array.from(sig));
        
        // execute spend limit change privately
        await escrow
            .withWallet(user)
            .methods
            .change_spend_limit_by_signature(spendLimitChange, signature)
            .send()
            .wait();
        
        // check new spend limit
        const spendLimit = await escrow.withWallet(user).methods.get_spend_limit().simulate() as bigint;
        expect(spendLimit).toBe(spendLimitChange);

        // deposit some tokens into the escrow
        await depositToEscrow(
            escrow,
            user,
            usdc,
            MINT_AMOUNT,
        );

        // withdraw from the escrow by signature
        const withdrawAmount = wad(1000n, 6n);
        nonce = await escrow.withWallet(operator).methods.get_nonce().simulate();
        const withdrawSignature = await buildSignedEscrowMessage(
            signingKey,
            escrow.address,
            withdrawAmount,
            nonce,
            "withdraw"
        ).then(sig => Array.from(sig));

        await escrow
            .withWallet(user)
            .methods
            .withdraw_by_signature(withdrawAmount, withdrawSignature)
            .send()
            .wait();
            
        // check balances after withdrawal
        expect(
            expectBalancePrivate(usdc, user.getAddress(), MINT_AMOUNT - withdrawAmount)
        ).toBeTruthy();
        expect(expectBalancePrivate(usdc, escrow.address, MINT_AMOUNT - withdrawAmount)).toBeTruthy();
    })

    test.skip("e2e", async () => {
        // ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
        //     userPXE,
        //     user,
        //     usdc.address,
        //     operator.getAddress(),
        //     INITIAL_SPEND_LIMIT
        // ));

        // // give operator knowledge of the escrow
        // await operatorPXE.registerAccount(escrowMasterKey, await escrow.partialAddress);
        // await operatorPXE.registerContract(escrow);
        // await escrow.withWallet(operator).methods.sync_private_state().simulate();

        // // check balances before
        // usdc = usdc.withWallet(user);
        // expect(expectBalancePrivate(usdc, user.getAddress(), MINT_AMOUNT)).toBeTruthy();
        // expect(expectBalancePrivate(usdc, escrow.address, 0n)).toBeTruthy();

        // // deposit tokens into the escrow
        // await depositToEscrow(
        //     escrow,
        //     user,
        //     usdc,
        //     MINT_AMOUNT,
        // );

        // // check USDC balances after transfer in
        // usdc = usdc.withWallet(user);
        // expect(
        //     expectBalancePrivate(usdc, user.getAddress(), 0n)
        // ).toBeTruthy();
        // expect(expectBalancePrivate(usdc, escrow.address, MINT_AMOUNT)).toBeTruthy();

        // // spend some tokens from the escrow twice
        // let epoch = await computeEpoch(cheatcodes);

        // await escrow
        //     .withWallet(operator)
        //     .methods.spend(INITIAL_SPEND_LIMIT / 2n, epoch)
        //     .send()
        //     .wait();

        // await escrow
        //     .withWallet(operator)
        //     .methods.spend(INITIAL_SPEND_LIMIT / 2n, epoch)
        //     .send()
        //     .wait();
        // expect(expectBalancePrivate(usdc, escrow.address, MINT_AMOUNT - INITIAL_SPEND_LIMIT)).toBeTruthy();
        // expect(expectBalancePrivate(usdc, operator.getAddress(), INITIAL_SPEND_LIMIT)).toBeTruthy();

        // // advance epoch and try to spend again
        // console.log("1")
        // let currentTimestamp = await userCC.eth.timestamp();
        // console.log("current timestamp: ", currentTimestamp)
        // await userCC.eth.warp(currentTimestamp + 86400);
        // await operatorCC.eth.warp(currentTimestamp + 86400);
        // console.log("warped to ", currentTimestamp + 86400)
        // // mine a block on l1 and send a tx on l2 to ensure the timestamp change takes effect
        // await userCC.eth.mine(1);
        // await operatorCC.eth.mine(1);
        // console.log("mined 1 block on l1")
        // await usdc
        //     .withWallet(minter)
        //     .methods.mint_to_private(
        //         minter.getAddress(),
        //         minter.getAddress(),
        //         1
        //     )
        //     .send()
        //     .wait();
        // console.log("sent tx on l2")
        // epoch = epoch.add(Fr.ONE);
        // console.log("Next epoch: ", epoch.toBigInt());

        // spend again
        // await escrow
        //     .withWallet(operator)
        //     .methods.spend(INITIAL_SPEND_LIMIT, epoch)
        //     .send()
        //     .wait();
        // expect(expectBalancePrivate(usdc, escrow.address, MINT_AMOUNT - (2n * INITIAL_SPEND_LIMIT))).toBeTruthy();
        // expect(expectBalancePrivate(usdc, operator.getAddress(), 2n * INITIAL_SPEND_LIMIT)).toBeTruthy();

        // withdraw some tokens from the escrow
        // await escrow
        //     .withWallet(user)
        //     .methods.prepare_withdrawal(INITIAL_SPEND_LIMIT)
        //     .send()
        //     .wait();

        // // advance 30 l2 blocks
        // await 
    });
});

// // deploy new escrow instance
//         ({ contract: escrow, secretKey: escrowMasterKey } = await deployEscrowContract(
//             userPXE,
//             seller,
//             usdc.address,
//             sellTokenAmount,
//             eth.address,
//             buyTokenAmount,
//         ));

//         // check balances before
//         usdc = usdc.withWallet(seller);
//         expect(expectBalancePrivate(usdc, seller.getAddress(), sellerUSDCInitialBalance)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, 0n)).toBeTruthy();

//         // deposit tokens into the escrow
//         await depositToEscrow(
//             escrow,
//             seller,
//             usdc,
//             sellTokenAmount,
//         );

//         // check USDC balances after transfer in
//         usdc = usdc.withWallet(seller);
//         expect(
//             expectBalancePrivate(usdc, seller.getAddress(), sellerUSDCInitialBalance - sellTokenAmount)
//         ).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, sellTokenAmount)).toBeTruthy();


//         // check buyer balance balances before filling order
//         usdc = usdc.withWallet(buyer);
//         eth = eth.withWallet(buyer);
//         expect(expectBalancePrivate(eth, seller.getAddress(), buyerETHInitialBalance)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, seller.getAddress(), 0n)).toBeTruthy();
//         expect(expectBalancePrivate(eth, escrow.address, 0n)).toBeTruthy();

//         // give buyer knowledge of the escrow
// await operatorPXE.registerAccount(escrowMasterKey, await escrow.partialAddress);
// await operatorPXE.registerContract(escrow);
// await escrow.withWallet(buyer).methods.sync_private_state().simulate();

//         // transfer tokens back out
//         await fillOTCOrder(escrow, buyer, eth, buyTokenAmount);

//         // check balances after filling order
//         expect(
//             expectBalancePrivate(eth, buyer.getAddress(), buyerETHInitialBalance - buyTokenAmount)
//         ).toBeTruthy();
//         expect(expectBalancePrivate(usdc, buyer.getAddress(), sellTokenAmount)).toBeTruthy();
//         expect(expectBalancePrivate(eth, seller.getAddress(), buyTokenAmount)).toBeTruthy();
//         expect(expectBalancePrivate(usdc, escrow.address, 0n)).toBeTruthy();