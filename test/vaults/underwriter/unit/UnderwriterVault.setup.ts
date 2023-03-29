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
      const collateral = parseUnits(
        (5 * strike).toString(),
        await quote.decimals(),
      );
      const totalSize = collateral.add(fee);
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
  });
});
