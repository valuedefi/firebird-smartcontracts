import {expect} from '../chai-setup';
import {ethers} from 'hardhat';
import {Contract, ContractFactory, BigNumber, utils} from 'ethers';
import {Provider} from '@ethersproject/providers';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

import {
    ADDRESS_ZERO, MAX_UINT256, fromWei, toWei,
    getLatestBlock,
    getLatestBlockNumber,
    getLatestBlockTime,
    mineBlocks, mineBlockTimeStamp, mineOneBlock, setNextBlockTimestamp
} from '../shared/utilities';

const ONE_WEEK_SECONDS = 7 * 24 * 3600;
const INITIAL_AMOUNT = utils.parseEther('1000');

const TX01 = '0xe8f9b445d4d2012878f4c410572d62cf781fc16a9111bb91e74a69501951bee1';
const TX02 = '0xc1e52d478a803b2f5930d6e525cd89dea6713fd8f38c06dfd6ffcb52f0140d15';
const TX03 = '0x898fae641c0c0dbf794677db973bb6c656f6530aa45365110cccc891ef27efe0';

describe('VbswapToHopePearlBridge.test', () => {
    const {provider} = ethers;

    let operator: SignerWithAddress;
    let admin: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;
    let david: SignerWithAddress;

    before('provider & accounts setting', async () => {
        [operator, admin, bob, carol, david] = await ethers.getSigners();
    });

    // core
    let vBSWAP: ContractFactory;
    let HopePearl: ContractFactory;
    let VbswapToHopePearlBridge: ContractFactory;

    before('fetch contract factories', async () => {
        vBSWAP = await ethers.getContractFactory('vBSWAP');
        HopePearl = await ethers.getContractFactory('HopePearl');
        VbswapToHopePearlBridge = await ethers.getContractFactory('VbswapToHopePearlBridge');
    });

    let vbswap: Contract;
    let pearl: Contract;
    let bridge: Contract;

    let startReleaseTime: BigNumber;
    let endReleaseTime: BigNumber;

    before('deploy contracts', async () => {
        vbswap = await vBSWAP.connect(operator).deploy("vBSWAP", "vBSWAP", 18, toWei('100000'));

        pearl = await HopePearl.connect(operator).deploy();
        await pearl.connect(operator).initialize(toWei('1000000000'));

        startReleaseTime = BigNumber.from(String(await getLatestBlockTime(ethers))).add(60);

        bridge = await VbswapToHopePearlBridge.connect(operator).deploy();
        await bridge.connect(operator).initialize(vbswap.address, pearl.address, startReleaseTime, 100000000, 5000000);

        await pearl.connect(operator).setMinterCap(bridge.address, toWei('100000000'));
    });

    describe('#constructor', () => {
        it('should works correctly', async () => {
            expect(String(await bridge.startReleaseTime())).to.eq(String(startReleaseTime));
            expect(String(await bridge.passedWeeks())).to.eq(toWei('0'));
            expect(String(await bridge.migrateRate())).to.eq('100000000');
        });

        it('should fail if initialize twice', async () => {
            await expect(bridge.connect(operator).initialize(vbswap.address, pearl.address, startReleaseTime, 100000000, 10000000)).to.revertedWith('Contract instance has already been initialized');
        });
    });

    describe('#migrate', () => {
        it('should fail if migrate too early', async () => {
            await expect(bridge.connect(bob).migrate(toWei('10'))).to.be.revertedWith('migration not opened yet');
        });

        it('should fail if migrate more than balance', async () => {
            const latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + 3600);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            await expect(bridge.connect(bob).migrate(toWei('10'))).to.be.revertedWith('transfer amount exceeds balance');
        });

        it('should fail if migrate before approve', async () => {
            await vbswap.connect(operator).mint(bob.address, toWei('1000'));
            await expect(bridge.connect(bob).migrate(toWei('10'))).to.be.revertedWith('transfer amount exceeds allowance');
        });

        it('bob migrate 10 vBSWAP', async () => {
            await vbswap.connect(bob).approve(bridge.address, MAX_UINT256);
            await expect(async () => {
                await bridge.connect(bob).migrate(toWei('10'));
            }).to.changeTokenBalances(pearl, [bob, bridge], [toWei('100000'), toWei('0')]);
            expect(String(await vbswap.balanceOf(bob.address))).to.eq(toWei('990'));
            expect(String(await bridge.totalBurned())).to.eq(toWei('10'));
            expect(String(await bridge.totalMinted())).to.eq(toWei('100000'));
        });
    });

    describe('#reduce rate', () => {
        it('go to next weeks', async () => {
            expect(String(await bridge.passedWeeks())).to.eq(toWei('0'));
            expect(String(await bridge.migrateRate())).to.eq('100000000');
            let latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + ONE_WEEK_SECONDS);
            await mineOneBlock(ethers);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            expect(String(await bridge.passedWeeks())).to.eq('1');
            expect(String(await bridge.migrateRate())).to.eq('95000000');
            latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + ONE_WEEK_SECONDS);
            await mineOneBlock(ethers);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            expect(String(await bridge.passedWeeks())).to.eq('2');
            expect(String(await bridge.migrateRate())).to.eq('90000000');
            await expect(async () => {
                await bridge.connect(bob).migrate(toWei('10'));
            }).to.changeTokenBalances(pearl, [bob, bridge], [toWei('90000'), toWei('0')]);
        });

        it('go to week #21 (rate is 0)', async () => {
            let latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + ONE_WEEK_SECONDS * 19);
            await mineOneBlock(ethers);
            console.log('latestBlockTime = %s', await getLatestBlockTime(ethers));
            expect(String(await bridge.passedWeeks())).to.eq('21');
            expect(String(await bridge.migrateRate())).to.eq('0');
            await expect(bridge.connect(bob).migrate(toWei('10'))).to.be.revertedWith('zero rate');
        });
    });
});
