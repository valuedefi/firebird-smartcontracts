import {expect} from "../chai-setup";
import {ethers} from 'hardhat';
import {Contract, ContractFactory, BigNumber, utils} from 'ethers';
import {Provider} from '@ethersproject/providers';
import {SignerWithAddress} from 'hardhat-deploy-ethers/dist/src/signer-with-address';

import {
    ADDRESS_ZERO, fromWei,
    getLatestBlock,
    getLatestBlockNumber, getLatestBlockTime,
    MAX_UINT256,
    mineBlocks, mineBlockTimeStamp, mineOneBlock, setNextBlockTimestamp,
    toWei
} from "../shared/utilities";

const ONE_DAY_SECONDS = 24 * 3600;
const INITIAL_AMOUNT = utils.parseEther('1000');

async function latestBlocktime(provider: Provider): Promise<number> {
    const {timestamp} = await provider.getBlock('latest');
    return timestamp;
}

async function latestBlocknumber(provider: Provider): Promise<number> {
    return await provider.getBlockNumber();
}

describe('mHopeStakingPool.test', () => {
    const {provider} = ethers;

    let operator: SignerWithAddress;
    let reserveFund: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;
    let david: SignerWithAddress;

    before('provider & accounts setting', async () => {
        // @ts-ignore
        [operator, reserveFund, bob, carol, david] = await ethers.getSigners();
    });

    // core
    let mHopeStakingPool: ContractFactory;
    let TToken: ContractFactory;

    before('fetch contract factories', async () => {
        mHopeStakingPool = await ethers.getContractFactory('mHopeStakingPool');
        TToken = await ethers.getContractFactory('TToken');
    });

    let pool: Contract;
    let lp: Contract;
    let usdc: Contract;

    let startReleaseTime: BigNumber;

    before('deploy contracts', async () => {
        lp = await TToken.connect(operator).deploy('Fake LP', 'LP', 18);
        usdc = await TToken.connect(operator).deploy('USD Coin', 'USDC', 18);

        startReleaseTime = BigNumber.from(String(await getLatestBlockTime(ethers))).add(60);
        pool = await mHopeStakingPool.connect(operator).deploy();
        await pool.initialize(lp.address, usdc.address, startReleaseTime);
        await pool.setReserveFund(reserveFund.address);

        await lp.mint(bob.address, toWei('1000'));
        await usdc.mint(reserveFund.address, toWei('1000'));
    });

    describe('#constructor', () => {
        it('should works correctly', async () => {
            expect(String(await pool.startRewardTime())).to.eq(startReleaseTime);
            expect(String(await pool.endRewardTime())).to.eq(startReleaseTime);
            expect(String(await pool.owner())).to.eq(operator.address);
            expect(String(await pool.reserveFund())).to.eq(reserveFund.address);
            expect(String(await pool.stakeToken())).to.eq(lp.address);
            expect(String(await pool.rewardToken())).to.eq(usdc.address);
        });

        it('should fail if initialize twice', async () => {
            await expect(pool.connect(operator).initialize(lp.address, usdc.address, startReleaseTime)).to.revertedWith('Contract instance has already been initialized');
        });
    });

    describe('#deposit/withdraw', () => {
        it('bob deposit 10 LP', async () => {
            await lp.connect(bob).approve(pool.address, MAX_UINT256);
            await pool.connect(bob).deposit(toWei('10'));
        });

        it('allocateMoreRewards', async () => {
            await usdc.connect(reserveFund).approve(pool.address, MAX_UINT256);
            let latestBlockTime = await getLatestBlockTime(ethers);
            await pool.connect(reserveFund).allocateMoreRewards(toWei('10'), 7);
            expect(await pool.endRewardTime()).to.gte( BigNumber.from(latestBlockTime + ONE_DAY_SECONDS * 7));
            console.log('RewardPoolInfo = %s', JSON.stringify([await pool.rewardPerSecond(), await pool.accRewardPerShare()]));
        });

        it('bob withdraw 10 LP', async () => {
            let latestBlockTime = await getLatestBlockTime(ethers);
            await setNextBlockTimestamp(ethers, latestBlockTime + ONE_DAY_SECONDS);
            await mineOneBlock(ethers);
            console.log('bob pending reward USDC = %s', fromWei(await pool.pendingReward(bob.address)));
            await expect(async () => {
                await pool.connect(bob).withdraw(toWei('5'));
            }).to.changeTokenBalances(lp, [bob, pool], [toWei('5'), toWei('-5')]);
            expect(String(await usdc.balanceOf(bob.address))).to.eq( toWei('1.427643217326527720'));
        });

        it('allocateMoreRewards#2', async () => {
            expect(String(await pool.rewardPerSecond())).to.eq( toWei('0.000016533024716871'));
            await pool.connect(reserveFund).allocateMoreRewards(toWei('10'), 1);
            expect(String(await pool.rewardPerSecond())).to.eq( toWei('0.000030704430862650'));
        });
    });
});
