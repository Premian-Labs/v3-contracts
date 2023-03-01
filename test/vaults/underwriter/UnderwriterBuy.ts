import { expect } from 'chai';
import { ethers } from 'hardhat';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { parseEther, formatEther, formatUnits } from 'ethers/lib/utils';
import { BigNumberish, BigNumber } from 'ethers';
import { vaultSetup, addDeposit } from './VaultSetup';
import { IPoolMock__factory } from '../../../typechain';
import { time } from '@nomicfoundation/hardhat-network-helpers';
import { TokenType } from '../../../utils/sdk/types';
import { getValidMaturity } from '../../../utils/time';

describe('#Vault contract', () => {
  it('properly initializes vault variables', async () => {
    const { vault, lastTimeStamp } = await loadFixture(vaultSetup);

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
      await vault.getClevelParams();

    expect(parseFloat(formatEther(minClevel))).to.eq(1.0);
    expect(parseFloat(formatEther(maxClevel))).to.eq(1.2);
    expect(parseFloat(formatEther(alphaClevel))).to.eq(3.0);
    expect(parseFloat(formatEther(hourlyDecayDiscount))).to.eq(0.005);

    [minDTE, maxDTE, minDelta, maxDelta] = await vault.getTradeBounds();

    expect(parseFloat(formatEther(minDTE))).to.eq(3.0);
    expect(parseFloat(formatEther(maxDTE))).to.eq(30.0);
    expect(parseFloat(formatEther(minDelta))).to.eq(0.1);
    expect(parseFloat(formatEther(maxDelta))).to.eq(0.7);

    _lastTradeTimestamp = await vault.getLastTradeTimestamp();
    // check that a timestamp was set
    expect(_lastTradeTimestamp).to.eq(lastTimeStamp);
    // check timestamp is in seconds epoch
    expect(_lastTradeTimestamp.toString().length).to.eq(10);
  });

  it('should properly initialize a new option pool', async () => {
    const { p, poolKey, poolAddress } = await loadFixture(vaultSetup);
    expect(await p.poolFactory.getPoolAddress(poolKey)).to.eq(poolAddress);
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

  it('responds to mock oracle adapter query', async () => {
    const { oracleAdapter, base, quote } = await loadFixture(vaultSetup);
    const price = await oracleAdapter.quote(base.address, quote.address);
    expect(parseFloat(formatUnits(price, 18))).to.eq(1500);
  });

  it('responds to mock iv oracle query', async () => {
    const { volOracle, base } = await loadFixture(vaultSetup);
    const iv = await volOracle[
      'getVolatility(address,uint256,uint256,uint256)'
    ](base.address, parseEther('2500'), parseEther('2000'), parseEther('0.2'));
    expect(parseFloat(formatEther(iv))).to.eq(0.8054718161126052);
  });
});

describe('#buy functionality', () => {
  describe('#quote functionality', () => {
    it('determines the appropriate collateral amt', async () => {});

    it('reverts on no strike input', async () => {
      const { lp, vault } = await loadFixture(vaultSetup);
      const badStrike = parseEther('0'); // ATM
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const quoteSize = parseEther('1');
      const lpDepositSize = 5; // units of base
      await addDeposit(vault.address, lp, lpDepositSize);
      await expect(
        vault.quote(badStrike, maturity, quoteSize),
      ).to.be.revertedWithCustomError(vault, 'Vault__StrikeZero');
    });

    it('reverts on expired maturity input', async () => {
      const { lp, vault } = await loadFixture(vaultSetup);
      const badStrike = parseEther('1500'); // ATM
      const maturity = await time.latest();
      const quoteSize = parseEther('1');
      const lpDepositSize = 5; // units of base
      await addDeposit(vault.address, lp, lpDepositSize);
      await expect(
        vault.quote(badStrike, maturity, quoteSize),
      ).to.be.revertedWithCustomError(vault, 'Vault__OptionExpired');
    });

    it('gets a valid spot price via the vault', async () => {
      const { vault } = await loadFixture(vaultSetup);
      const spotPrice = await vault.getSpotPrice();
      expect(parseFloat(formatEther(spotPrice))).to.be.equal(1500);
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

    describe('#isValidListing functionality', () => {
      it('returns a valid listing address', async () => {
        const { vault } = await loadFixture(vaultSetup);
      });

      it('reverts on invalid maturity bounds', async () => {});

      it('retrieves valid option delta', async () => {});

      it('reverts on invalid option delta bounds', async () => {});

      it('receives a valid option address', async () => {});

      it('returns the proper pool address from factory', async () => {
        const { p, poolKey, poolAddress } = await loadFixture(vaultSetup);
        const listingAddr = await p.poolFactory.getPoolAddress(poolKey);
        expect(listingAddr).to.be.eq(poolAddress);
      });

      it('returns addressZero from factory non existing pool', async () => {
        const { base, quote, maturity, isCall, oracleAdapter, p } =
          await loadFixture(vaultSetup);
        const nonExistingPoolKey = {
          base: base.address,
          quote: quote.address,
          oracleAdapter: oracleAdapter.address,
          strike: parseEther('1600'), // ATM,
          maturity: BigNumber.from(maturity),
          isCallPool: isCall,
        };
        const listingAddr = await p.poolFactory.getPoolAddress(
          nonExistingPoolKey,
        );
        expect(listingAddr).to.be.eq(ethers.constants.AddressZero);
      });

      it('reverts when factory returns addressZERO', async () => {
        const { lp, vault } = await loadFixture(vaultSetup);
        await loadFixture(vaultSetup);
      });
    });

    it('returns the proper blackscholes price', async () => {});

    it('calculates the proper mintingFee', async () => {});

    it('checks if the vault has sufficient funds', async () => {});

    describe('#cLevel functionality', () => {
      it('should have a totalSpread that is positive', async () => {});

      it('reverts if maxCLevel is not set properly', async () => {});

      it(' reverts if the C level alpha is not set properly', async () => {});

      it('used post quote/trade utilization', async () => {});

      it('ensures utilization never goes over 100%', async () => {});

      it('properly checks for last trade timestamp', async () => {});

      describe('#cLevel calculation', () => {
        it('will not exceed max c Level', async () => {});

        it('will properly adjust based on utilization', async () => {});
      });

      it('properly decays the c Level over time', async () => {});

      it('will not go below min c Level', async () => {});
    });
  });

  describe('#addListing functionality', () => {
    it('will insert maturity if it does not exist', async () => {});

    it('will properly add a strike only once', async () => {});

    it('will update the doublylinked list max maturity if needed', async () => {});
  });

  describe('#minting options from pool', () => {
    it('allows writeFrom to mint options when directly called', async () => {
      const { underwriter, trader, base, poolAddress } = await loadFixture(
        vaultSetup,
      );
      const size = parseEther('5');
      const callPool = IPoolMock__factory.connect(poolAddress, underwriter);
      const fee = await callPool.takerFee(size, 0, true);
      const totalSize = size.add(fee);
      await base.connect(underwriter).approve(callPool.address, totalSize);
      await callPool.writeFrom(underwriter.address, trader.address, size);
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
    it('allows the vault to mint options for the LP and Trader', async () => {
      const { lp, trader, base, vault } = await loadFixture(vaultSetup);
      const lpDepositSize = 5; // units of base
      await addDeposit(vault.address, lp, lpDepositSize);
      const strike = parseEther('1500');
      const maturity = BigNumber.from(await getValidMaturity(2, 'weeks'));
      const tradeSize = parseEther('2');
      // FIXME: divide by zero error (likely up stream)
      // await vault.connect(trader).buy(strike, maturity, tradeSize);
    });
  });

  describe('#afterBuy', () => {
    //TODO: merge afterbuy from UnderwriterBuy.ts
  });
});
