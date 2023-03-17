import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { addMockDeposit, p, vaultSetup } from '../VaultSetup';
import {
  formatEther,
  formatUnits,
  parseEther,
  parseUnits,
} from 'ethers/lib/utils';
import { BigNumber, BigNumberish } from 'ethers';
import { expect } from 'chai';
import { ethers } from 'hardhat';
import { IPoolMock__factory } from '../../../../typechain';
import { TokenType } from '../../../../utils/sdk/types';
import { getValidMaturity } from '../../../../utils/time';

describe('#vaultSetup', () => {
  // TODO: what does this test?
  it('returns addressZero from factory non existing pool', async () => {
    const { base, quote, maturity, oracleAdapter, p } = await loadFixture(
      vaultSetup,
    );
    for (const isCall of [true, false]) {
      const nonExistingPoolKey = {
        base: base.address,
        quote: quote.address,
        oracleAdapter: oracleAdapter.address,
        strike: parseEther('500'), // ATM,
        maturity: BigNumber.from(maturity),
        isCallPool: isCall,
      };
      const listingAddr = await p.poolFactory.getPoolAddress(
        nonExistingPoolKey,
      );
      expect(listingAddr).to.be.eq(ethers.constants.AddressZero);
    }
  });

  it('returns the proper pool address from factory', async () => {
    const { p, callPoolKey, callPool } = await loadFixture(vaultSetup);
    const listingAddr = await p.poolFactory.getPoolAddress(callPoolKey);
    expect(listingAddr).to.be.eq(callPool.address);
  });

  it('gets a valid iv value via vault', async () => {
    const { volOracle, base } = await loadFixture(vaultSetup);
    const spot = parseEther('1500');
    const strike = parseEther('1500'); // ATM
    const maturity = parseEther('0.03835616'); // 2 weeks
    const iv = await volOracle[
      'getVolatility(address,uint256,uint256,uint256)'
    ](base.address, spot, strike, maturity);

    expect(parseFloat(formatEther(iv))).to.be.eq(0.7340403881444237);
  });

  it('responds to mock oracle adapter query', async () => {
    const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
    const price = await oracleAdapter.quote(base.address, quote.address);
    expect(parseFloat(formatUnits(price, 18))).to.eq(1500);
  });

  it('test correct initialisation of the vaults storage variables', async () => {
    const { callVault, lastTimeStamp } = await loadFixture(vaultSetup);

    let minClevel: BigNumberish;
    let maxClevel: BigNumberish;
    let alphaClevel: BigNumberish;
    let hourlyDecayDiscount: BigNumberish;
    let minDTE: BigNumberish;
    let maxDTE: BigNumberish;
    let minDelta: BigNumberish;
    let maxDelta: BigNumberish;
    let _lastTradeTimestamp: BigNumberish;

    [minClevel, maxClevel, alphaClevel, hourlyDecayDiscount] =
      await callVault.getClevelParams();

    expect(parseFloat(formatEther(minClevel))).to.eq(1.0);
    expect(parseFloat(formatEther(maxClevel))).to.eq(1.2);
    expect(parseFloat(formatEther(alphaClevel))).to.eq(3.0);
    expect(parseFloat(formatEther(hourlyDecayDiscount))).to.eq(0.005);

    [minDTE, maxDTE, minDelta, maxDelta] = await callVault.getTradeBounds();

    expect(parseFloat(formatEther(minDTE))).to.eq(3.0);
    expect(parseFloat(formatEther(maxDTE))).to.eq(30.0);
    expect(parseFloat(formatEther(minDelta))).to.eq(0.1);
    expect(parseFloat(formatEther(maxDelta))).to.eq(0.7);

    _lastTradeTimestamp = await callVault.getLastTradeTimestamp();
    // check that a timestamp was set
    expect(_lastTradeTimestamp).to.eq(lastTimeStamp);
    // check timestamp is in seconds epoch
    expect(_lastTradeTimestamp.toString().length).to.eq(10);
  });

  it('should properly initialize a new option pool', async () => {
    const { p, callPoolKey, callPool } = await loadFixture(vaultSetup);
    expect(await p.poolFactory.getPoolAddress(callPoolKey)).to.eq(
      callPool.address,
    );
  });

  it('should properly hydrate accounts with funds', async () => {
    const { base, quote, deployer, caller, receiver, underwriter, trader } =
      await loadFixture(vaultSetup);
    expect(await base.balanceOf(deployer.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(caller.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(receiver.address)).to.equal(parseEther('1000'));
    expect(await base.balanceOf(underwriter.address)).to.equal(
      parseEther('1000'),
    );
    expect(await base.balanceOf(trader.address)).to.equal(parseEther('1000'));

    expect(await quote.balanceOf(deployer.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(caller.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(receiver.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(underwriter.address)).to.equal(
      parseEther('1000000'),
    );
    expect(await quote.balanceOf(trader.address)).to.equal(
      parseEther('1000000'),
    );
  });
  it('retrieves valid option delta', async () => {
    const { callVault, putVault, base, volOracle } = await loadFixture(
      vaultSetup,
    );
    const spotPrice = await callVault['getSpotPrice()']();
    const strike = parseEther('1500');
    const tau = parseEther('0.03835616'); // 14 DTE
    const rfRate = await volOracle.getRiskFreeRate();
    const sigma = await volOracle[
      'getVolatility(address,uint256,uint256,uint256)'
    ](base.address, spotPrice, strike, tau);
    const callDelta = await callVault.getDelta(
      spotPrice,
      strike,
      tau,
      sigma,
      rfRate,
      true,
    );

    const putDelta = await putVault.getDelta(
      spotPrice,
      strike,
      tau,
      sigma,
      rfRate,
      false,
    );

    expect(parseFloat(formatEther(callDelta))).to.approximately(0.528, 0.001);
    expect(parseFloat(formatEther(putDelta))).to.approximately(-0.471, 0.001);
  });

  describe('#minting options from pool', () => {
    it('allows writeFrom to mint call options when directly called', async () => {
      const { underwriter, trader, base, callPool, p } = await loadFixture(
        vaultSetup,
      );
      const size = parseEther('5');
      const callPoolUnderwriter = IPoolMock__factory.connect(
        callPool.address,
        underwriter,
      );
      const fee = await callPool.takerFee(size, 0, true);
      const totalSize = size.add(fee);
      await base.connect(underwriter).approve(p.router.address, totalSize);
      await callPoolUnderwriter.writeFrom(
        underwriter.address,
        trader.address,
        size,
      );
      expect(await base.balanceOf(callPool.address)).to.eq(totalSize);
      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        size,
      );
      expect(await callPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(
        0,
      );
      expect(
        await callPool.balanceOf(underwriter.address, TokenType.LONG),
      ).to.eq(0);
      expect(
        await callPool.balanceOf(underwriter.address, TokenType.SHORT),
      ).to.eq(size);
    });

    it('allows writeFrom to mint put options when directly called', async () => {
      const { underwriter, trader, quote, putPool } = await loadFixture(
        vaultSetup,
      );
      const size = parseEther('5');
      const strike = 1500;
      const putPoolUnderwriter = IPoolMock__factory.connect(
        putPool.address,
        underwriter,
      );
      const fee = await putPool.takerFee(size, 0, false);
      const totalSize = size.mul(strike).add(fee);
      console.log(totalSize);
      await quote.connect(underwriter).approve(p.router.address, totalSize);
      await putPoolUnderwriter.writeFrom(
        underwriter.address,
        trader.address,
        size,
      );
      expect(await quote.balanceOf(putPool.address)).to.eq(totalSize);
      expect(await putPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        size,
      );
      expect(await putPool.balanceOf(trader.address, TokenType.SHORT)).to.eq(0);
      expect(
        await putPool.balanceOf(underwriter.address, TokenType.LONG),
      ).to.eq(0);
      expect(
        await putPool.balanceOf(underwriter.address, TokenType.SHORT),
      ).to.eq(size);
    });

    it('allows the vault to mint call options for the LP and Trader', async () => {
      const { callVault, lp, trader, base, quote, callPool } =
        await loadFixture(vaultSetup);
      const lpDepositSize = 5; // units of base
      const lpDepositSizeBN = parseEther(lpDepositSize.toString());
      await addMockDeposit(callVault, lpDepositSize, base, quote);
      const strike = parseEther('1500');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');

      const [, premium, mintingFee, , spread] = await callVault.quote(
        strike,
        maturity,
        tradeSize,
      );

      const totalTransfer = premium.add(mintingFee).add(spread);

      await base.connect(trader).approve(callVault.address, totalTransfer);
      await callVault
        .connect(trader)
        .trade(strike, maturity, true, tradeSize, true);
      const vaultCollateralBalance = lpDepositSizeBN
        .sub(tradeSize)
        .add(premium)
        .add(spread);

      // todo: cover the put case
      // collateral
      expect(await base.balanceOf(callPool.address)).to.eq(
        tradeSize.add(mintingFee),
      );

      expect(await callPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
        tradeSize,
      );
      expect(
        await callPool.balanceOf(callVault.address, TokenType.SHORT),
      ).to.eq(tradeSize);
      // as time passes the B-Sch. price and C-level change
      expect(
        parseFloat(formatEther(await base.balanceOf(callVault.address))),
      ).to.be.closeTo(
        parseFloat(formatEther(vaultCollateralBalance)),
        0.000001,
      );
    });

    it('allows the vault to mint put options for the LP and Trader', async () => {
      const { putVault, lp, trader, base, quote, putPool } = await loadFixture(
        vaultSetup,
      );

      const strike = 1500;
      const lpDepositSize = 5 * strike; // 5 units
      const lpDepositSizeBN = parseUnits(lpDepositSize.toString(), 6);
      await addMockDeposit(putVault, lpDepositSize, base, quote);

      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');
      const fee = await putPool.takerFee(tradeSize, 0, false);
      const totalSize = tradeSize.add(fee);
      const strikeBN = parseEther(strike.toString());
      // FIXME: these tests will not run because writeFrom decimalization for puts is incorrect

      // await putVault.connect(trader).trade(strikeBN, maturity, false, tradeSize, true);
      // const vaultCollateralBalance = lpDepositSizeBN.sub(totalSize);

      // expect(await quote.balanceOf(putPool.address)).to.eq(totalSize);
      // expect(await putPool.balanceOf(trader.address, TokenType.LONG)).to.eq(
      //   tradeSize,
      // );
      // expect(await putPool.balanceOf(putVault.address, TokenType.SHORT)).to.eq(
      //   tradeSize,
      // );
      // expect(await quote.balanceOf(putVault.address)).to.be.eq(
      //   vaultCollateralBalance,
      // );
    });
  });
});
