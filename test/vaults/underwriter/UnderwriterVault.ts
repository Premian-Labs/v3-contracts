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
import { now, ONE_DAY } from '../../../utils/time';
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

  before(async () => {
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

    const vaultProxy = await new UnderwriterVaultProxy__factory(
      deployer,
    ).deploy(
      vaultImpl.address,
      base.address,
      quote.address,
      baseOracle.address,
      'WETH Vault',
      'WETH',
      true,
    );
    await vaultProxy.deployed();

    vault = UnderwriterVaultMock__factory.connect(vaultProxy.address, deployer);

    if (log) console.log(`UnderwriterVaultProxy : ${vaultProxy.address}`);
  });

  describe('#vault environment after a single trade', () => {
    const prepareVault = async () => {
      const assetAmount = parseEther('2');
      await base.connect(caller).approve(vault.address, assetAmount);
      await vault.connect(caller).deposit(assetAmount, receiver.address);

      // description of environment / fixture
      // deposit: 2 collateral
      // trade: buys 1 option contract, 0.5 premium, spread 0.1, maturity 10 (days), dte 10, strike 100
      // premium

      // get block time, set min maturity as the block time + 10 days
      let currentTime = await now();
      const strike = await parseEther('100');
      const positionSize = await parseEther('1');
      const minMaturity = currentTime + 10 * ONE_DAY;
      await vault.setMinMaturity(minMaturity.toString());
      await vault.setMaxMaturity(minMaturity.toString());
      await vault.insertMaturity(0, minMaturity);
      await vault.insertMaturity(minMaturity, 2 * minMaturity);
      await vault.insertStrike(minMaturity, strike);
      await vault.setTotalLockedSpread(parseEther('0.1'));
      await vault.setLastSpreadUnlockUpdate(currentTime);
      await vault.setSpreadUnlockingRate('115740740740');
      await vault.setSpreadUnlockingTick(minMaturity, '115740740740');
      await vault.setTotalLockedAssets(parseEther('1'));
      // deposited 2 assets, 0.5 premiums, 0.1 spread
      await vault.setTotalAssets(parseEther('2.6'));
      await vault.setPositionSize(minMaturity, strike, positionSize);
      console.log(await vault.getTotalFairValue());
    };

    it('prepare Vault', async () => {
      await prepareVault();
      console.log(parseFloat(formatEther(await vault.getPricePerShare())));
    });
  });

  describe('#convertToShares', () => {
    it('if no shares have been minted, minted shares should equal deposited assets', async () => {
      const assetAmount = parseEther('2');
      const shareAmount = await vault.convertToShares(assetAmount);
      expect(shareAmount).to.eq(assetAmount);
    });
  });

  describe('#convertToAssets', () => {
    //TODO:
    it('if total ', async () => {
      const shareAmount = parseEther('2');
      const assetAmount = await vault.convertToAssets(shareAmount);
      expect(shareAmount).to.eq(assetAmount);
    });
  });

  describe('#maxDeposit', () => {
    it('', async () => {
      const assetAmount = await vault.maxDeposit(receiver.address);
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
      await vault.connect(deployer).setTotalLockedSpread(parseEther('0.5'));
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

  describe('#mint', () => {
    it('two consecutive mints', async () => {
      const shareAmount = parseEther('2');
      const baseBalanceCaller = await base.balanceOf(caller.address);
      const baseBalanceReceiver = await base.balanceOf(receiver.address);

      const allowedAssetAmount = parseEther('4');
      await base.connect(caller).approve(vault.address, allowedAssetAmount);
      await vault.connect(caller).deposit(shareAmount, receiver.address);

      expect(await base.balanceOf(vault.address)).to.eq(shareAmount);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(shareAmount),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(await vault.balanceOf(receiver.address)).to.eq(shareAmount);
      expect(await vault.totalAssets()).to.eq(shareAmount);
      expect(await vault.totalSupply()).to.eq(shareAmount);

      await vault.connect(caller).deposit(shareAmount, receiver.address);
      expect(await base.balanceOf(vault.address)).to.eq(allowedAssetAmount);
      expect(await base.balanceOf(caller.address)).to.eq(
        baseBalanceCaller.sub(allowedAssetAmount),
      );
      expect(await base.balanceOf(receiver.address)).to.eq(baseBalanceReceiver);
      expect(await vault.balanceOf(caller.address)).to.eq(parseEther('0'));
      expect(await vault.balanceOf(receiver.address)).to.eq(allowedAssetAmount);
    });
  });

  describe('#withdraw', () => {
    it('simple withdraw', async () => {
      const withdrawAssetAmount = parseEther('3');
      const allowedAssetAmount = parseEther('4');
      await base.connect(receiver).approve(vault.address, allowedAssetAmount);
      await vault
        .connect(receiver)
        .deposit(allowedAssetAmount, receiver.address);
      await vault
        .connect(receiver)
        .withdraw(withdrawAssetAmount, receiver.address, receiver.address);
    });
  });
});
