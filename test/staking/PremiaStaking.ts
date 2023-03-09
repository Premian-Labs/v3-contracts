import { expect } from 'chai';
import {
  ERC20Mock__factory,
  ExchangeHelper__factory,
  PremiaStakingMock,
  PremiaStakingMock__factory,
  PremiaStakingProxyMock__factory,
} from '../../typechain';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { signERC2612Permit } from 'eth-permit';
import { parseEther, parseUnits } from 'ethers/lib/utils';
import { BigNumber, BigNumberish } from 'ethers';
import { increase, increaseTo, ONE_YEAR } from '../../utils/time';
import { bnToNumber } from '../../utils/sdk/math';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';

const ONE_DAY = 3600 * 24;
const USDC_DECIMALS = 6;

function parseUSDC(amount: string) {
  return parseUnits(amount, USDC_DECIMALS);
}

function decay(
  pendingRewards: number,
  oldTimestamp: number,
  newTimestamp: number,
) {
  return Math.pow(1 - 2.7e-7, newTimestamp - oldTimestamp) * pendingRewards;
}

async function bridge(
  fromUser: SignerWithAddress,
  premiaStaking: PremiaStakingMock,
  otherPremiaStaking: PremiaStakingMock,
  user: SignerWithAddress,
  amount: BigNumberish,
  stakePeriod: number,
  lockedUntil: number,
) {
  // Mocked bridge out
  await premiaStaking
    .connect(fromUser)
    .sendFrom(
      user.address,
      0,
      user.address,
      amount,
      user.address,
      ethers.constants.AddressZero,
      '0x',
    );

  // Mocked bridge in
  await otherPremiaStaking.creditTo(
    user.address,
    amount,
    stakePeriod,
    lockedUntil,
  );
}

describe('PremiaStaking', () => {
  async function deploy() {
    const [admin, alice, bob, carol] = await ethers.getSigners();

    const premia = await new ERC20Mock__factory(admin).deploy('PREMIA', 18);
    const usdc = await new ERC20Mock__factory(admin).deploy(
      'USDC',
      USDC_DECIMALS,
    );
    const exchangeHelper = await new ExchangeHelper__factory(admin).deploy();
    const premiaStakingImplementation = await new PremiaStakingMock__factory(
      admin,
    ).deploy(
      ethers.constants.AddressZero,
      premia.address,
      usdc.address,
      exchangeHelper.address,
    );

    const premiaStakingProxy = await new PremiaStakingProxyMock__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    const otherPremiaStakingProxy = await new PremiaStakingProxyMock__factory(
      admin,
    ).deploy(premiaStakingImplementation.address);

    const premiaStaking = PremiaStakingMock__factory.connect(
      premiaStakingProxy.address,
      admin,
    );

    const otherPremiaStaking = PremiaStakingMock__factory.connect(
      otherPremiaStakingProxy.address,
      admin,
    );

    await usdc.mint(admin.address, parseUSDC('1000'));
    await premia.mint(alice.address, parseEther('100'));
    await premia.mint(bob.address, parseEther('100'));
    await premia.mint(carol.address, parseEther('100'));

    await usdc
      .connect(admin)
      .approve(premiaStaking.address, ethers.constants.MaxUint256);

    return {
      admin,
      alice,
      bob,
      carol,
      premia,
      usdc,
      premiaStakingImplementation,
      premiaStaking,
      otherPremiaStaking,
      exchangeHelper,
    };
  }

  describe('#getTotalVotingPower', () => {
    it('should successfully return total voting power', async () => {
      const { premia, premiaStaking, alice, bob } = await loadFixture(deploy);
      expect(await premiaStaking.getTotalPower()).to.eq(0);

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('1.25'));

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getTotalPower()).to.eq(parseEther('3.5'));
    });
  });

  describe('#getUserVotingPower', () => {
    it('should successfully return user voting power', async () => {
      const { premia, premiaStaking, alice, bob } = await loadFixture(deploy);

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking.connect(alice).stake(parseEther('1'), ONE_DAY * 365);

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premiaStaking
        .connect(bob)
        .stake(parseEther('3'), (ONE_DAY * 365) / 2);

      expect(await premiaStaking.getUserPower(alice.address)).to.eq(
        parseEther('1.25'),
      );
      expect(await premiaStaking.getUserPower(bob.address)).to.eq(
        parseEther('2.25'),
      );
    });
  });

  describe('FeeDiscount', () => {
    const stakeAmount = parseEther('120000');
    const oneMonth = 30 * ONE_DAY;

    async function deployAndInitialize() {
      const f = await deploy();
      await f.premia.mint(f.alice.address, stakeAmount);
      await f.premia
        .connect(f.alice)
        .increaseAllowance(
          f.premiaStaking.address,
          ethers.constants.MaxUint256,
        );

      return f;
    }

    it('should stake and calculate discount successfully', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(
        deployAndInitialize,
      );

      await premiaStaking.connect(alice).stake(stakeAmount, ONE_YEAR);
      let amountWithBonus = await premiaStaking.getUserPower(alice.address);
      expect(amountWithBonus).to.eq(parseEther('150000'));
      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(2722);

      await increase(ONE_YEAR + 1);

      await premiaStaking.connect(alice).startWithdraw(parseEther('10000'));

      amountWithBonus = await premiaStaking.getUserPower(alice.address);

      expect(amountWithBonus).to.eq(parseEther('137500'));
      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(2694);

      await premia.mint(alice.address, parseEther('5000000'));
      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('5000000'));
      await premiaStaking.connect(alice).stake(parseEther('5000000'), ONE_YEAR);

      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(6000);
    });

    it('should stake successfully with permit', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(
        deployAndInitialize,
      );

      const { timestamp } = await ethers.provider.getBlock('latest');
      const deadline = timestamp + 3600;

      const result = await signERC2612Permit(
        alice.provider,
        premia.address,
        alice.address,
        premiaStaking.address,
        stakeAmount.toString(),
        deadline,
      );

      await premiaStaking
        .connect(alice)
        .stakeWithPermit(
          stakeAmount,
          ONE_YEAR,
          deadline,
          result.v,
          result.r,
          result.s,
        );

      const amountWithBonus = await premiaStaking.getUserPower(alice.address);
      expect(amountWithBonus).to.eq(parseEther('150000'));
    });

    it('should fail unstaking if stake is still locked', async () => {
      const { premiaStaking, alice } = await loadFixture(deployAndInitialize);

      await premiaStaking.connect(alice).stake(stakeAmount, oneMonth);
      await expect(
        premiaStaking.connect(alice).startWithdraw(1),
      ).to.be.revertedWithCustomError(
        premiaStaking,
        'PremiaStaking__StakeLocked',
      );
    });

    it('should correctly calculate stake period multiplier', async () => {
      const { premiaStaking } = await loadFixture(deployAndInitialize);

      expect(await premiaStaking.getStakePeriodMultiplierBPS(0)).to.eq(2500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(ONE_YEAR / 2),
      ).to.eq(7500);
      expect(await premiaStaking.getStakePeriodMultiplierBPS(ONE_YEAR)).to.eq(
        12500,
      );
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(2 * ONE_YEAR),
      ).to.eq(22500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(4 * ONE_YEAR),
      ).to.eq(42500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(5 * ONE_YEAR),
      ).to.eq(42500);
    });
  });

  it('should fail transferring tokens', async () => {
    const { premia, premiaStaking, alice, bob } = await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await expect(
      premiaStaking.connect(alice).transfer(bob.address, parseEther('1')),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__CantTransfer',
    );
  });

  it('should successfully stake with permit', async () => {
    const { premia, premiaStaking, alice } = await loadFixture(deploy);

    const { timestamp } = await ethers.provider.getBlock('latest');
    const deadline = timestamp + 3600;

    const result = await signERC2612Permit(
      alice.provider,
      premia.address,
      alice.address,
      premiaStaking.address,
      parseEther('100').toString(),
      deadline,
    );

    await premiaStaking
      .connect(alice)
      .stakeWithPermit(
        parseEther('100'),
        0,
        deadline,
        result.v,
        result.r,
        result.s,
      );
    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should not allow enter if not enough approve', async () => {
    const { premia, premiaStaking, alice } = await loadFixture(deploy);

    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'ERC20Base__InsufficientAllowance',
    );
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('50'));
    await expect(
      premiaStaking.connect(alice).stake(parseEther('100'), 0),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'ERC20Base__InsufficientAllowance',
    );
    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    const balance = await premiaStaking.balanceOf(alice.address);
    expect(balance).to.eq(parseEther('100'));
  });

  it('should only allow to withdraw what is available', async () => {
    const { premia, premiaStaking, alice, bob, otherPremiaStaking } =
      await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await premia
      .connect(bob)
      .approve(otherPremiaStaking.address, parseEther('40'));
    await otherPremiaStaking.connect(bob).stake(parseEther('20'), 0);

    await bridge(
      alice,
      premiaStaking,
      otherPremiaStaking,
      alice,
      parseEther('50'),
      0,
      0,
    );

    await premiaStaking.connect(alice).startWithdraw(parseEther('50'));
    await otherPremiaStaking.connect(alice).startWithdraw(parseEther('10'));
    await otherPremiaStaking.connect(bob).startWithdraw(parseEther('5'));

    await expect(
      otherPremiaStaking.connect(alice).startWithdraw(parseEther('10')),
    ).to.be.revertedWithCustomError(
      otherPremiaStaking,
      'PremiaStaking__NotEnoughLiquidity',
    );
  });

  it('should correctly handle withdrawal with delay', async () => {
    const { premia, premiaStaking, alice } = await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premiaStaking.connect(alice).stake(parseEther('100'), 0);

    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__NoPendingWithdrawal',
    );

    await premiaStaking.connect(alice).startWithdraw(parseEther('40'));

    expect(await premiaStaking.getAvailablePremiaAmount()).to.eq(
      parseEther('60'),
    );

    await increase(ONE_DAY * 10 - 5);
    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__WithdrawalStillPending',
    );

    await increase(10);

    await premiaStaking.connect(alice).withdraw();
    expect(await premiaStaking.balanceOf(alice.address)).to.eq(
      parseEther('60'),
    );
    expect(await premia.balanceOf(alice.address)).to.eq(parseEther('40'));

    await expect(
      premiaStaking.connect(alice).withdraw(),
    ).to.be.revertedWithCustomError(
      premiaStaking,
      'PremiaStaking__NoPendingWithdrawal',
    );
  });

  it('should distribute partial rewards properly', async () => {
    const { premia, premiaStaking, alice, bob, carol, admin } =
      await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    await premiaStaking.connect(bob).startWithdraw(parseEther('10'));

    // PremiaStaking get 50 USDC rewards
    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    expect((await premiaStaking.getPendingWithdrawal(bob.address))[0]).to.eq(
      parseEther('10'),
    );

    await increase(ONE_DAY * 30);

    const pendingRewards = await premiaStaking.getPendingRewards();

    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      pendingRewards.mul(10).div(40),
    );
  });

  it('should work with more than one participant', async () => {
    const { premia, premiaStaking, alice, bob, carol, admin } =
      await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));
    await premia.connect(bob).approve(premiaStaking.address, parseEther('100'));
    await premia
      .connect(carol)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('30'), 0);
    await premiaStaking.connect(bob).stake(parseEther('10'), 0);
    await premiaStaking.connect(carol).stake(parseEther('10'), 0);

    let aliceBalance = await premiaStaking.balanceOf(alice.address);
    let bobBalance = await premiaStaking.balanceOf(bob.address);
    let carolBalance = await premiaStaking.balanceOf(carol.address);
    let contractBalance = await premia.balanceOf(premiaStaking.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('10'));
    expect(carolBalance).to.eq(parseEther('10'));
    expect(contractBalance).to.eq(parseEther('50'));

    await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

    let { timestamp } = await ethers.provider.getBlock('latest');

    await increase(ONE_DAY * 30);

    const pendingRewards1 = await premiaStaking.getPendingRewards();
    let availableRewards = await premiaStaking.getAvailableRewards();

    let decayValue = BigNumber.from(
      Math.floor(
        decay(50, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );

    expect(pendingRewards1).to.eq(parseUSDC('50').sub(decayValue));
    expect(availableRewards[0]).to.eq(
      parseUSDC('50').sub(parseUSDC('50').sub(decayValue)),
    );
    expect(availableRewards[1]).to.eq(0);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      pendingRewards1.mul(30).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      pendingRewards1.mul(10).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      pendingRewards1.mul(10).div(50),
    );

    await increase(ONE_DAY * 300000);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50),
    );

    await premiaStaking.connect(bob).stake(parseEther('50'), 0);

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('30'));
    expect(bobBalance).to.eq(parseEther('60'));
    expect(carolBalance).to.eq(parseEther('10'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('5'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('20'));

    aliceBalance = await premiaStaking.balanceOf(alice.address);
    bobBalance = await premiaStaking.balanceOf(bob.address);
    carolBalance = await premiaStaking.balanceOf(carol.address);

    expect(aliceBalance).to.eq(parseEther('25'));
    expect(bobBalance).to.eq(parseEther('40'));
    expect(carolBalance).to.eq(parseEther('10'));

    // Pending withdrawals should not count anymore as staked
    await premiaStaking.connect(admin).addRewards(parseUSDC('100'));
    timestamp = (await ethers.provider.getBlock('latest')).timestamp;

    await increase(ONE_DAY * 30);

    const pendingRewards2 = await premiaStaking.getPendingRewards();
    availableRewards = await premiaStaking.getAvailableRewards();
    decayValue = BigNumber.from(
      Math.floor(
        decay(100, timestamp, timestamp + ONE_DAY * 30) *
          Math.pow(10, USDC_DECIMALS),
      ),
    );

    expect(pendingRewards2).to.eq(parseUSDC('100').sub(decayValue));
    expect(availableRewards[0]).to.eq(
      parseUSDC('100').sub(parseUSDC('100').sub(decayValue)),
    );
    expect(availableRewards[1]).to.eq(0);

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50).add(pendingRewards2.mul(25).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(pendingRewards2.mul(40).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(pendingRewards2.mul(10).div(75)),
    );

    await increase(ONE_DAY * 300000);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();

    let alicePremiaBalance = await premia.balanceOf(alice.address);
    let bobPremiaBalance = await premia.balanceOf(bob.address);

    // Alice = 100 - 30 + 5
    expect(alicePremiaBalance).to.eq(parseEther('75'));
    // Bob = 100 - 10 - 50 + 20
    expect(bobPremiaBalance).to.eq(parseEther('60'));

    await premiaStaking.connect(alice).startWithdraw(parseEther('25'));
    await premiaStaking.connect(bob).startWithdraw(parseEther('40'));
    await premiaStaking.connect(carol).startWithdraw(parseEther('10'));

    await increase(10 * ONE_DAY + 1);

    await premiaStaking.connect(alice).withdraw();
    await premiaStaking.connect(bob).withdraw();
    await premiaStaking.connect(carol).withdraw();

    alicePremiaBalance = await premia.balanceOf(alice.address);
    bobPremiaBalance = await premia.balanceOf(bob.address);
    const carolPremiaBalance = await premia.balanceOf(carol.address);

    expect(await premiaStaking.totalSupply()).to.eq(0);
    expect(alicePremiaBalance).to.eq(parseEther('100'));
    expect(bobPremiaBalance).to.eq(parseEther('100'));
    expect(carolPremiaBalance).to.eq(parseEther('100'));

    expect((await premiaStaking.getPendingUserRewards(alice.address))[0]).to.eq(
      parseUSDC('50').mul(30).div(50).add(parseUSDC('100').mul(25).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(bob.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(parseUSDC('100').mul(40).div(75)),
    );
    expect((await premiaStaking.getPendingUserRewards(carol.address))[0]).to.eq(
      parseUSDC('50').mul(10).div(50).add(parseUSDC('100').mul(10).div(75)),
    );
  });

  it('should correctly calculate decay', async () => {
    const { premiaStaking } = await loadFixture(deploy);

    const oneMonth = 30 * ONE_DAY;
    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth)),
    ).to.eq(49.66647168721973);

    expect(
      bnToNumber(await premiaStaking.decay(parseEther('100'), 0, oneMonth * 2)),
    ).to.eq(24.667584098573993);
  });

  it('should correctly bridge to other contract', async () => {
    const { premia, premiaStaking, alice, otherPremiaStaking } =
      await loadFixture(deploy);

    await premia
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    await premiaStaking.connect(alice).stake(parseEther('100'), 365 * ONE_DAY);
    await premiaStaking
      .connect(alice)
      .approve(premiaStaking.address, parseEther('100'));

    expect(await premiaStaking.totalSupply()).to.eq(parseEther('100'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(0);

    await bridge(
      alice,
      premiaStaking,
      otherPremiaStaking,
      alice,
      parseEther('10'),
      0,
      0,
    );

    expect(await premia.balanceOf(premiaStaking.address)).to.eq(
      parseEther('100'),
    );
    expect(await premia.balanceOf(otherPremiaStaking.address)).to.eq(0);
    expect(await premiaStaking.totalSupply()).to.eq(parseEther('90'));
    expect(await otherPremiaStaking.totalSupply()).to.eq(parseEther('10'));
  });

  describe('#getStakeLevels', () => {
    it('should correctly return stake levels', async () => {
      const { premiaStaking } = await loadFixture(deploy);

      expect(await premiaStaking.getStakeLevels()).to.deep.eq([
        [parseEther('5000'), parseEther('0.1')],
        [parseEther('50000'), parseEther('0.25')],
        [parseEther('500000'), parseEther('0.35')],
        [parseEther('2500000'), parseEther('0.6')],
      ]);
    });
  });

  describe('#harvest', () => {
    it('should correctly harvest pending rewards of user', async () => {
      const { premia, premiaStaking, alice, bob, carol, admin, usdc } =
        await loadFixture(deploy);

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('100'));
      await premia
        .connect(carol)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking.connect(alice).stake(parseEther('30'), 0);
      await premiaStaking.connect(bob).stake(parseEther('10'), 0);
      await premiaStaking.connect(carol).stake(parseEther('10'), 0);

      await premiaStaking.connect(admin).addRewards(parseUSDC('50'));

      await increase(ONE_DAY * 30);

      const aliceRewards = await premiaStaking.getPendingUserRewards(
        alice.address,
      );

      await premiaStaking.connect(alice).harvest();
      expect(await usdc.balanceOf(alice.address)).to.eq(aliceRewards[0].add(3)); // Amount is slightly higher because block timestamp increase by 1 second on harvest
      expect(
        (await premiaStaking.getPendingUserRewards(alice.address))[0],
      ).to.eq(0);
    });
  });

  describe('#harvestAndStake', () => {
    it('harvests rewards, converts to PREMIA, and stakes', async () => {
      // ToDo : Update to use fork mode
      // await premia
      //   .connect(alice)
      //   .approve(premiaStaking.address, parseEther('100'));
      // await premia
      //   .connect(bob)
      //   .approve(premiaStaking.address, parseEther('100'));
      // await premia
      //   .connect(carol)
      //   .approve(premiaStaking.address, parseEther('100'));
      //
      // await premiaStaking.connect(alice).stake(parseEther('30'), 0);
      // await premiaStaking.connect(bob).stake(parseEther('10'), 0);
      // await premiaStaking.connect(carol).stake(parseEther('10'), 0);
      //
      // await premiaStaking.connect(admin).addRewards(parseUSDC('50'));
      //
      // await increase(ONE_DAY * 30);
      //
      // const aliceRewards = await premiaStaking.getPendingUserRewards(
      //   alice.address,
      // );
      //
      // const amountBefore = await premiaStaking.callStatic.balanceOf(
      //   alice.address,
      // );
      //
      // const uniswapPath = [usdc.address, uniswap.weth.address, premia.address];
      //
      // const { timestamp } = await ethers.provider.getBlock('latest');
      //
      // const totalRewards = aliceRewards[0].add(aliceRewards[1]);
      //
      // const iface = new ethers.utils.Interface(uniswapABIs);
      // const data = iface.encodeFunctionData('swapExactTokensForTokens', [
      //   totalRewards,
      //   ethers.constants.Zero,
      //   uniswapPath,
      //   exchangeHelper.address,
      //   ethers.constants.MaxUint256,
      // ]);
      //
      // await premiaStaking.connect(alice).harvestAndStake(
      //   {
      //     amountOutMin: ethers.constants.Zero,
      //     callee: uniswap.router.address,
      //     allowanceTarget: uniswap.router.address,
      //     data,
      //     refundAddress: alice.address,
      //   },
      //   ethers.constants.Zero,
      // );
      //
      // const amountAfter = await premiaStaking.balanceOf(alice.address);
      //
      // expect(amountAfter).to.be.gt(amountBefore);
    });
  });

  describe('#earlyUnstake', () => {
    it('should correctly apply early unstake fee and distribute it to stakers', async () => {
      const { premia, premiaStaking, alice, bob, carol } = await loadFixture(
        deploy,
      );

      await premia
        .connect(bob)
        .approve(premiaStaking.address, parseEther('50'));

      await premiaStaking.connect(bob).stake(parseEther('50'), 365 * ONE_DAY);

      //

      await premia
        .connect(carol)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking
        .connect(carol)
        .stake(parseEther('100'), 365 * ONE_DAY);

      //

      await premia
        .connect(alice)
        .approve(premiaStaking.address, parseEther('100'));

      await premiaStaking
        .connect(alice)
        .stake(parseEther('100'), 4 * 365 * ONE_DAY);

      //

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        7500,
      );

      await increase(2 * 365 * ONE_DAY);

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        5000,
      );

      await premiaStaking.connect(alice).earlyUnstake(parseEther('100'));

      expect(
        (await premiaStaking.connect(alice).getPendingWithdrawal(alice.address))
          .amount,
      ).to.eq(parseEther('50.0000007927447996')); // Small difference due to block timestamp increase by 1 second on new block mined

      const totalFee = parseEther('100').sub(parseEther('50.0000007927447996'));
      const bobFeeReward = totalFee.div(3);
      const carolFeeReward = totalFee.mul(2).div(3);

      expect(
        (await premiaStaking.getPendingUserRewards(bob.address)).unstakeReward,
      ).to.eq(bobFeeReward);
      expect(
        (await premiaStaking.getPendingUserRewards(carol.address))
          .unstakeReward,
      ).to.eq(carolFeeReward);

      await premiaStaking.connect(bob).harvest();

      expect(await premiaStaking.balanceOf(bob.address)).to.eq(
        parseEther('50').add(bobFeeReward),
      );

      await premiaStaking.connect(carol).harvest();

      expect(await premiaStaking.balanceOf(carol.address)).to.eq(
        parseEther('100').add(carolFeeReward),
      );
    });
  });

  describe('#updateLock', () => {
    it('should correctly increase user lock', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      await premia.connect(alice).approve(premiaStaking.address, 1000);
      await premiaStaking.connect(alice).stake(1000, 0);
      let block = await ethers.provider.getBlock('latest');

      let uInfo = await premiaStaking.getUserInfo(alice.address);
      expect(uInfo.stakePeriod).to.eq(0);
      expect(uInfo.lockedUntil).to.eq(block.timestamp);
      expect(await premiaStaking.getUserPower(alice.address)).to.eq(250);
      expect(await premiaStaking.getTotalPower()).to.eq(250);

      await premiaStaking.connect(alice).updateLock(ONE_YEAR * 2);
      block = await ethers.provider.getBlock('latest');

      uInfo = await premiaStaking.getUserInfo(alice.address);
      expect(uInfo.stakePeriod).to.eq(ONE_YEAR * 2);
      expect(uInfo.lockedUntil).to.eq(block.timestamp + ONE_YEAR * 2);
      expect(await premiaStaking.getUserPower(alice.address)).to.eq(2250);
      expect(await premiaStaking.getTotalPower()).to.eq(2250);
    });
  });

  describe('#getDiscount', () => {
    it('should successfully return discount', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      const amount = parseEther('10000');
      await premia.mint(alice.address, amount);
      await premia.connect(alice).approve(premiaStaking.address, amount);
      await premiaStaking.connect(alice).stake(amount, 2.5 * ONE_YEAR);

      // Period multiplier of x2.75
      expect(
        await premiaStaking.getStakePeriodMultiplier(2.5 * ONE_YEAR),
      ).to.eq(parseEther('2.75'));

      // Total power of 10000 * 2.75 = 27500
      expect(await premiaStaking.getUserPower(alice.address)).to.eq(
        parseEther('27500'),
      );

      // 27500 is halfway between first and second stake level -> 5000 + ((50 000 - 5000) / 2) = 27500
      // Therefore expected discount is halfway between first and second discount level -> 0.1 + ((0.25 - 0.1) / 2) = 0.175
      expect(await premiaStaking.getDiscount(alice.address)).to.eq(
        parseEther('0.175'),
      );
    });
  });

  describe('#getDiscountBPS', () => {
    it('should successfully return discount', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      const amount = parseEther('10000');
      await premia.mint(alice.address, amount);
      await premia.connect(alice).approve(premiaStaking.address, amount);
      await premiaStaking.connect(alice).stake(amount, 2.5 * ONE_YEAR);

      // Period multiplier of x2.75
      expect(
        await premiaStaking.getStakePeriodMultiplier(2.5 * ONE_YEAR),
      ).to.eq(parseEther('2.75'));

      // Total power of 10000 * 2.75 = 27500
      expect(await premiaStaking.getUserPower(alice.address)).to.eq(
        parseEther('27500'),
      );

      // 27500 is halfway between first and second stake level -> 5000 + ((50 000 - 5000) / 2) = 27500
      // Therefore expected discount is halfway between first and second discount level -> 0.1 + ((0.25 - 0.1) / 2) = 0.175
      expect(await premiaStaking.getDiscountBPS(alice.address)).to.eq(1750);
    });
  });

  describe('#getStakePeriodMultiplier', () => {
    it('should successfully return stake period multiplier', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      expect(await premiaStaking.getStakePeriodMultiplier(0)).to.eq(
        parseEther('0.25'),
      );
      expect(await premiaStaking.getStakePeriodMultiplier(ONE_YEAR)).to.eq(
        parseEther('1.25'),
      );
      expect(
        await premiaStaking.getStakePeriodMultiplier(1.5 * ONE_YEAR),
      ).to.eq(parseEther('1.75'));
      expect(await premiaStaking.getStakePeriodMultiplier(3 * ONE_YEAR)).to.eq(
        parseEther('3.25'),
      );
      expect(await premiaStaking.getStakePeriodMultiplier(5 * ONE_YEAR)).to.eq(
        parseEther('4.25'),
      );
    });
  });

  describe('#getStakePeriodMultiplierBPS', () => {
    it('should successfully return stake period multiplier in BPS', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      expect(await premiaStaking.getStakePeriodMultiplierBPS(0)).to.eq(2500);
      expect(await premiaStaking.getStakePeriodMultiplierBPS(ONE_YEAR)).to.eq(
        12500,
      );
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(1.5 * ONE_YEAR),
      ).to.eq(17500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(3 * ONE_YEAR),
      ).to.eq(32500);
      expect(
        await premiaStaking.getStakePeriodMultiplierBPS(5 * ONE_YEAR),
      ).to.eq(42500);
    });
  });

  describe('#getEarlyUnstakeFee', () => {
    it('should successfully return early unstake fee', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      await premia.connect(alice).approve(premiaStaking.address, 1000);
      await premiaStaking.connect(alice).stake(1000, 4 * ONE_YEAR);
      let block = await ethers.provider.getBlock('latest');

      expect(await premiaStaking.getEarlyUnstakeFee(alice.address)).to.eq(
        parseEther('0.75'),
      );

      await increaseTo(block.timestamp + 2 * ONE_YEAR);

      expect(await premiaStaking.getEarlyUnstakeFee(alice.address)).to.eq(
        parseEther('0.5'),
      );
    });
  });

  describe('#getEarlyUnstakeFeeBPS', () => {
    it('should successfully return early unstake fee in BPS', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      await premia.connect(alice).approve(premiaStaking.address, 1000);
      await premiaStaking.connect(alice).stake(1000, 4 * ONE_YEAR);
      let block = await ethers.provider.getBlock('latest');

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        7500,
      );

      await increaseTo(block.timestamp + 2 * ONE_YEAR);

      expect(await premiaStaking.getEarlyUnstakeFeeBPS(alice.address)).to.eq(
        5000,
      );
    });
  });

  describe('#sendFrom', () => {
    it('should not revert if no approval but owner', async () => {
      const { premia, premiaStaking, alice } = await loadFixture(deploy);

      await premia.connect(alice).approve(premiaStaking.address, 1);
      await premiaStaking.connect(alice).stake(1, 0);

      await premiaStaking
        .connect(alice)
        .sendFrom(
          alice.address,
          0,
          alice.address,
          1,
          alice.address,
          ethers.constants.AddressZero,
          '0x',
        );
    });

    describe('reverts if', () => {
      it('sender is not approved or owner', async () => {
        const { premiaStaking, alice } = await loadFixture(deploy);

        await expect(
          premiaStaking
            .connect(alice)
            .sendFrom(
              premiaStaking.address,
              0,
              alice.address,
              1,
              alice.address,
              ethers.constants.AddressZero,
              '0x',
            ),
        ).to.be.revertedWithCustomError(
          premiaStaking,
          'OFT_InsufficientAllowance',
        );
      });
    });
  });
});