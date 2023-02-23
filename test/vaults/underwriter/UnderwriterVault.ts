import { expect } from 'chai';
import { ethers } from 'hardhat';
import {
  ERC20Mock,
  ERC20Mock__factory,
  IPoolMock__factory,
  UnderwriterVault__factory,
  UnderwriterVaultMock,
  UnderwriterVaultProxy,
  UnderwriterVaultMock__factory,
  UnderwriterVaultProxy__factory,
  IERC20__factory,
  VolatilityOracleMock,
  ProxyUpgradeableOwnable,
  VolatilityOracleMock__factory,
  ProxyUpgradeableOwnable__factory,
} from '../../../typechain';
import { BigNumber } from 'ethers';
import { IERC20 } from '../../../typechain';
import { SafeERC20 } from '../../../typechain';
import { now, ONE_DAY, increaseTo } from '../../../utils/time';
import { parseEther, parseUnits, formatEther } from 'ethers/lib/utils';
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { access } from 'fs';

describe('UnderwriterVault', () => {
  let deployer: SignerWithAddress;
  let caller: SignerWithAddress;
  let receiver: SignerWithAddress;
  let trader: SignerWithAddress;

  let vault: UnderwriterVaultMock;

  let base: ERC20Mock;
  let quote: ERC20Mock;
  let long: ERC20Mock;

  let baseOracle: MockContract;

  // ==================================================================
  // Setup volatility oracle
  let volOracle: VolatilityOracleMock;
  let volOracleProxy: ProxyUpgradeableOwnable;

  const paramsFormatted =
    '0x00004e39fe17a216e3e08d84627da56b60f41e819453f79b02b4cb97c837c2a8';
  const params = [
    0.839159148341129, -0.05957422656606383, 0.02004706385514592,
    0.14895038484273854, 0.034026549310791646,
  ].map((el) => Math.floor(el * 10 ** 12).toString());

  // ==================================================================

  const log = true;

  beforeEach(async () => {
    [deployer, caller, receiver, trader] = await ethers.getSigners();

    base = await new ERC20Mock__factory(deployer).deploy('WETH', 18);
    quote = await new ERC20Mock__factory(deployer).deploy('USDC', 6);
    long = await new ERC20Mock__factory(deployer).deploy('Short', 18);

    await base.deployed();
    await quote.deployed();
    await long.deployed();

    await base.mint(caller.address, parseEther('1000'));
    await quote.mint(caller.address, parseEther('1000000'));

    await base.mint(receiver.address, parseEther('1000'));
    await quote.mint(receiver.address, parseEther('1000000'));

    await base.mint(trader.address, parseEther('1000'));
    await quote.mint(trader.address, parseEther('1000000'));

    await base.mint(deployer.address, parseEther('1000'));
    await quote.mint(deployer.address, parseEther('1000000'));

    baseOracle = await deployMockContract(deployer as any, [
      'function latestAnswer() external view returns (int256)',
      'function decimals () external view returns (uint8)',
    ]);

    await baseOracle.mock.latestAnswer.returns(parseUnits('1', 8));
    await baseOracle.mock.decimals.returns(8);

    // Setup volatility oracle
    const impl = await new VolatilityOracleMock__factory(deployer).deploy();

    volOracleProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(impl.address);
    volOracle = VolatilityOracleMock__factory.connect(
      volOracleProxy.address,
      deployer,
    );

    await volOracle
      .connect(deployer)
      .addWhitelistedRelayers([deployer.address]);

    const tau = [
      0.0027397260273972603, 0.03561643835616438, 0.09315068493150686,
      0.16986301369863013, 0.4191780821917808,
    ].map((el) => Math.floor(el * 10 ** 12));

    const theta = [
      0.0017692409901229372, 0.01916765969267577, 0.050651452629040784,
      0.10109715579595925, 0.2708994887970898,
    ].map((el) => Math.floor(el * 10 ** 12));

    const psi = [
      0.037206384846952066, 0.0915623614722959, 0.16107355519602318,
      0.2824760899898832, 0.35798035117937516,
    ].map((el) => Math.floor(el * 10 ** 12));

    const rho = [
      1.3478910000157727e-8, 2.0145423645807155e-6, 2.910345029369492e-5,
      0.0003768214425074357, 0.0002539234691761822,
    ].map((el) => Math.floor(el * 10 ** 12));

    const tauHex = await volOracle.formatParams(tau as any);
    const thetaHex = await volOracle.formatParams(theta as any);
    const psiHex = await volOracle.formatParams(psi as any);
    const rhoHex = await volOracle.formatParams(rho as any);

    await volOracle
      .connect(deployer)
      .updateParams([base.address], [tauHex], [thetaHex], [psiHex], [rhoHex]);

    const vaultImpl = await new UnderwriterVaultMock__factory(deployer).deploy(
      volOracle.address,
      volOracle.address,
    );
    await vaultImpl.deployed();

    if (log)
      console.log(`UnderwriterVault Implementation : ${vaultImpl.address}`);

    // TODO: change base oracle address to oracle adapter
    const vaultProxy = await new UnderwriterVaultProxy__factory(
      deployer,
    ).deploy(
      vaultImpl.address,
      base.address,
      quote.address,
      baseOracle.address,
      baseOracle.address, // OracleAdapter
      'WETH Vault',
      'WETH',
      true,
    );
    await vaultProxy.deployed();

    vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);

    if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);
  });

  let startTime: number;
  let spot: number;
  let minMaturity: number;
  let maxMaturity: number;

  async function setupVault() {
    startTime = await now();
    spot = 2800;
    minMaturity = startTime + 10 * ONE_DAY;
    maxMaturity = startTime + 20 * ONE_DAY;

    await vault.setMinMaturity(minMaturity.toString());
    await vault.setMaxMaturity(maxMaturity.toString());
    await vault.insertMaturity(0, minMaturity);
    await vault.insertMaturity(minMaturity, 2 * maxMaturity);
  }

  async function addDeposit(
    caller: SignerWithAddress,
    receiver: SignerWithAddress,
    amount: number,
  ) {
    const assetAmount = parseEther(amount.toString());
    await base.connect(caller).approve(vault.address, assetAmount);
    await vault.connect(caller).deposit(assetAmount, receiver.address);
  }

  describe('#vault environment after a single trade', () => {
    async function addTrade(
      trader: SignerWithAddress,
      maturity: number,
      strike: number,
      amount: number,
      tradeTime: number,
      spread: number,
    ) {
      // trade: buys 1 option contract, 0.5 premium, spread 0.1, maturity 10 (days), dte 10, strike 100
      const strikeParsed = await parseEther(strike.toString());
      const amountParsed = await parseEther(amount.toString());
      //
      await vault.insertStrike(minMaturity, strikeParsed);

      await vault.increaseTotalLockedSpread(parseEther(spread.toString()));
      const additionalSpreadRate = (spread / (maturity - tradeTime)) * 10 ** 18;
      const spreadRate = additionalSpreadRate.toFixed(0).toString();
      await vault.setLastSpreadUnlockUpdate(tradeTime);
      await vault.increaseSpreadUnlockingRate(spreadRate);
      await vault.increaseSpreadUnlockingTick(minMaturity, spreadRate);
      await vault.increaseTotalLockedAssets(amountParsed);
      // we assume that the premium is just the exercise value for now
      const premium: number = (spot - strike) / spot;
      await vault.increaseTotalAssets(parseEther(premium.toString()));
      await vault.increaseTotalAssets(parseEther(spread.toString()));
      await vault.increasePositionSize(minMaturity, strikeParsed, amountParsed);
    }

    it('prepare Vault', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      await addTrade(trader, minMaturity, 1000, 1, startTime, 0.1);
      console.log(await vault.getTotalFairValue());

      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
      await increaseTo(minMaturity);
      console.log(await vault.getTotalFairValue());
      console.log(await vault.getTotalLockedSpread());
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
      await increaseTo(maxMaturity);
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
    });
  });

  describe('#convertToShares', () => {
    it('if no shares have been minted, minted shares should equal deposited assets', async () => {
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is one, minted shares equals the deposited assets', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 8);
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero, minted shares equals the deposited assets adjusted by the pricePerShare', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      await vault.increaseTotalLockedSpread(parseEther('1.0'));
      const assetAmount = 2;
      const shareAmount = await vault.convertToShares(
        parseEther(assetAmount.toString()),
      );
      expect(parseFloat(formatEther(shareAmount))).to.eq(2 * assetAmount);
    });
  });

  describe('#convertToAssets', () => {
    it('if total supply is zero, revert due to zero shares', async () => {
      const shareAmount = parseEther('2');
      await expect(
        vault.convertToAssets(shareAmount),
      ).to.be.revertedWithCustomError(vault, 'Vault__ZEROShares');
    });

    it('if supply is non-zero and pricePerShare is one, withdrawn assets equals share amount', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      const shareAmount = parseEther('2');
      const assetAmount = await vault.convertToAssets(shareAmount);
      expect(shareAmount).to.eq(assetAmount);
    });

    it('if supply is non-zero and pricePerShare is 0.5, withdrawn assets equals half the share amount', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      await vault.increaseTotalLockedSpread(parseEther('1.0'));
      const shareAmount = 2;
      const assetAmount = await vault.convertToAssets(
        parseEther(shareAmount.toString()),
      );
      expect(parseFloat(formatEther(assetAmount))).to.eq(0.5 * shareAmount);
    });
  });

  describe('#_availableAssets', () => {
    // availableAssets = totalAssets - totalLockedSpread - lockedAssets
    // totalAssets = totalDeposits + premiums + spread - exercise
    it('check formula for total available assets', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      expect(await vault.getAvailableAssets()).to.eq(parseEther('2'));
      await vault.increaseTotalLockedSpread(parseEther('0.002'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.998'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.498'));
      await vault.increaseTotalLockedSpread(parseEther('0.2'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.298'));
      await vault.increaseTotalLockedAssets(parseEther('0.0001'));
      expect(await vault.getAvailableAssets()).to.eq(parseEther('1.2979'));
    });
  });

  describe('#_maxWithdraw', () => {
    it('maxWithdraw should revert for a zero address', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      await expect(
        vault.maxWithdraw(ethers.constants.AddressZero),
      ).to.be.revertedWithCustomError(vault, 'Vault__AddressZero');
    });

    it('maxWithdraw should return the available assets for a non-zero address', async () => {
      await setupVault();
      await addDeposit(caller, receiver, 2);
      await vault.increaseTotalLockedSpread(parseEther('0.002'));
      await vault.increaseTotalLockedAssets(parseEther('0.5'));
      const assetAmount = await vault.maxWithdraw(receiver.address);
      expect(assetAmount).to.eq(parseEther('1.498'));
    });
  });

  describe('#previewDeposit', () => {
    it('', async () => {
      const assetAmount = parseEther('2');
      const sharesAmount = await vault.previewDeposit(assetAmount);
      console.log(formatEther(sharesAmount));
    });
  });

  describe('#maxMint', () => {
    it('', async () => {
      const test = await vault.maxMint(receiver.address);
      console.log(formatEther(test));
    });
  });

  describe('#previewMint', () => {
    it('', async () => {
      const sharesAmount = parseEther('2');
      const test = await vault.previewMint(sharesAmount);
      console.log(formatEther(test));
    });
  });

  describe('#deposit', () => {
    it('two consecutive deposits', async () => {
      const assetAmount = parseEther('2');
      const baseBalanceCaller = await base.balanceOf(caller.address);
      const baseBalanceReceiver = await base.balanceOf(receiver.address);

      const allowedAssetAmount = parseEther('4');
      await base.connect(caller).approve(vault.address, allowedAssetAmount);
      await vault.connect(caller).deposit(assetAmount, receiver.address);

      expect(await base.balanceOf(vault.address)).to.eq(assetAmount);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(assetAmount),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(await vault.balanceOf(receiver.address)).to.eq(assetAmount);
      //expect(await vault.totalAssets()).to.eq(assetAmount);
      expect(await vault.totalSupply()).to.eq(assetAmount);

      // modify the price per share to (1 - 0.5) / 1 = 0.5
      await vault
        .connect(deployer)
        .increaseTotalLockedSpread(parseEther('0.5'));
      await vault.connect(deployer).setMinMaturity(parseEther('1'));
      await vault.connect(caller).deposit(assetAmount, receiver.address);

      expect(await base.balanceOf(vault.address)).to.eq(allowedAssetAmount);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(allowedAssetAmount),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(
        parseFloat(formatEther(await vault.balanceOf(receiver.address))),
      ).to.be.closeTo(2 + 2 / 0.75, 0.00001);
    });
  });

  describe('#afterBuy', () => {
    const premium = 0.5;
    const spread = 0.1;
    const size = 1;
    const strike = 100;
    let maturity: number;
    let totalAssets: number;
    let spreadUnlockingRate: number;
    let afterBuyTimestamp: number;

    beforeEach(async () => {
      await setupVault();
      totalAssets = parseFloat(formatEther(await vault.totalAssets()));
      console.log('Setup vault.');

      maturity = minMaturity;
      spreadUnlockingRate = spread / (minMaturity - startTime);

      await vault.afterBuy(
        minMaturity,
        parseEther(premium.toString()),
        maturity - startTime,
        parseEther(size.toString()),
        parseEther(spread.toString()),
        parseEther(strike.toString()),
      );
      afterBuyTimestamp = await now();
      console.log('Processed afterBuy.');
    });

    it('lastSpreadUnlockUpdate should equal the time we executed afterBuy as we updated the state there', async () => {
      expect(await vault.lastSpreadUnlockUpdate()).to.eq(afterBuyTimestamp);
    });

    it('spreadUnlockingRates should equal', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingRate())),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('total assets should equal', async () => {
      expect(parseFloat(formatEther(await vault.totalAssets()))).to.eq(
        totalAssets + premium + spread,
      );
    });

    it('positionSize should equal should equal', async () => {
      const positionSize = await vault.positionSize(
        maturity,
        parseEther(strike.toString()),
      );
      expect(parseFloat(formatEther(positionSize))).to.eq(size);
    });

    it('spreadUnlockingRate / ticks', async () => {
      expect(
        parseFloat(formatEther(await vault.spreadUnlockingTicks(maturity))),
      ).to.be.closeTo(spreadUnlockingRate, 0.000000000000000001);
    });

    it('totalLockedAssets should equal', async () => {
      expect(parseFloat(formatEther(await vault.totalLockedAssets()))).to.eq(
        size,
      );
    });

    it('totalLockedSpread should equa', async () => {
      expect(parseFloat(formatEther(await vault.totalLockedSpread()))).to.eq(
        spread,
      );
    });
  });
});
