import { PricingMock__factory } from '../../typechain';
import { average } from '../../utils/sdk/math';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { parseEther } from 'ethers/lib/utils';
import { ethers } from 'hardhat';

describe('Pricing', () => {
  async function deploy() {
    const [deployer] = await ethers.getSigners();
    const instance = await new PricingMock__factory(deployer).deploy();

    return { deployer, instance };
  }

  before(async function () {});

  describe('#proportion', () => {
    it('should return the proportional amount', async () => {
      const { instance } = await loadFixture(deploy);

      for (const t of [
        [parseEther('0.25'), 0],
        [parseEther('0.75'), parseEther('1')],
        [parseEther('0.5'), parseEther('0.5')],
      ]) {
        expect(
          await instance.proportion(
            parseEther('0.25'),
            parseEther('0.75'),
            t[0],
          ),
        ).to.eq(t[1]);
      }
    });

    it('should revert if lower >= upper', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.proportion(parseEther('0.75'), parseEther('0.25'), 0),
      ).to.be.revertedWithCustomError(
        instance,
        'Pricing__UpperNotGreaterThanLower',
      );
    });

    it('should revert if lower > market || market > upper', async () => {
      const { instance } = await loadFixture(deploy);

      await expect(
        instance.proportion(
          parseEther('0.25'),
          parseEther('0.75'),
          parseEther('0.2'),
        ),
      ).to.be.revertedWithCustomError(instance, 'Pricing__PriceOutOfRange');

      await expect(
        instance.proportion(
          parseEther('0.25'),
          parseEther('0.75'),
          parseEther('0.8'),
        ),
      ).to.be.revertedWithCustomError(instance, 'Pricing__PriceOutOfRange');
    });
  });

  describe('#amountOfTicksBetween', () => {
    it('should correctly calculate amount of ticks between two values', async () => {
      const { instance } = await loadFixture(deploy);

      for (const t of [
        [parseEther('0.001'), parseEther('1'), parseEther('999')],
        [parseEther('0.05'), parseEther('0.95'), parseEther('900')],
        [parseEther('0.49'), parseEther('0.491'), parseEther('1')],
      ]) {
        expect(await instance.amountOfTicksBetween(t[0], t[1])).to.eq(t[2]);
      }
    });

    it('should revert if lower >= upper', async () => {
      for (const t of [
        [parseEther('0.2'), parseEther('0.01')],
        [parseEther('0.1'), parseEther('0.1')],
      ]) {
        const { instance } = await loadFixture(deploy);

        await expect(
          instance.amountOfTicksBetween(t[0], t[1]),
        ).to.be.revertedWithCustomError(
          instance,
          'Pricing__UpperNotGreaterThanLower',
        );
      }
    });
  });

  describe('#liquidity', () => {
    it('should return the liquidity', async () => {
      const { instance } = await loadFixture(deploy);

      for (const t of [
        [
          parseEther('1'),
          parseEther('0.001'),
          parseEther('1'),
          parseEther('999'),
        ],
        [
          parseEther('5'),
          parseEther('0.05'),
          parseEther('0.95'),
          parseEther('4500'),
        ],
        [
          parseEther('10'),
          parseEther('0.49'),
          parseEther('0.491'),
          parseEther('10'),
        ],
      ]) {
        const args = {
          liquidityRate: t[0],
          marketPrice: 0,
          lower: t[1],
          upper: t[2],
          isBuy: true,
        };

        expect(await instance.liquidity(args)).to.eq(t[3]);
      }
    });
  });

  describe('#bidLiquidity', () => {
    it('should return the bid liquidity', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'), // price == lower
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await instance.bidLiquidity(args)).to.eq(0);

      args.marketPrice = average(args.lower, args.upper); // price == average(lower, upper)

      expect(await instance.bidLiquidity(args)).to.eq(
        (await instance.liquidity(args)).div(2),
      );

      args.marketPrice = parseEther('0.75'); // price == upper

      expect(await instance.bidLiquidity(args)).to.eq(
        await instance.liquidity(args),
      );
    });
  });

  describe('#askLiquidity', () => {
    it('should return the ask liquidity', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'), // price == lower
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.askLiquidity(args)).to.eq(
        await instance.liquidity(args),
      );

      args.marketPrice = average(args.lower, args.upper); // price == average(lower, upper)

      expect(await instance.askLiquidity(args)).to.eq(
        (await instance.liquidity(args)).div(2),
      );

      args.marketPrice = parseEther('0.75'); // price == upper

      expect(await instance.askLiquidity(args)).to.eq(0);
    });
  });

  describe('#maxTradeSize', () => {
    it('should return the max trade size for buy order', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.maxTradeSize(args)).to.eq(
        await instance.askLiquidity(args),
      );
    });

    it('should return the max trade size for sell order', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await instance.maxTradeSize(args)).to.eq(
        await instance.bidLiquidity(args),
      );
    });
  });

  describe('#price', () => {
    it('should return upper tick for buy order if liquidity == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.price(args, 0)).to.eq(args.upper);
    });

    it('should return lower tick for sell order if liquidity == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await instance.price(args, 0)).to.eq(args.lower);
    });

    it('should return the price when trade size == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.price(args, 0)).to.eq(args.lower);

      args.isBuy = false;

      expect(await instance.price(args, 0)).to.eq(args.upper);
    });

    it('should return the price for buy order when liquidity > 0 && trade size > 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await instance.liquidity(args);
      let askLiq = await instance.askLiquidity(args);
      let bidLiq = await instance.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await instance.price(args, askLiq)).to.eq(args.lower);
      expect(await instance.price(args, bidLiq)).to.eq(args.upper);

      args.marketPrice = args.lower;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await instance.price(args, askLiq)).to.eq(args.upper);
      expect(await instance.price(args, bidLiq)).to.eq(args.lower);

      let _average = average(args.lower, args.upper);
      args.marketPrice = _average;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == average(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await instance.price(args, askLiq)).to.eq(_average);
      expect(await instance.price(args, bidLiq)).to.eq(_average);
    });

    it('should return the price for sell order when liquidity > 0 && trade size > 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      let liq = await instance.liquidity(args);
      let askLiq = await instance.askLiquidity(args);
      let bidLiq = await instance.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await instance.price(args, askLiq)).to.eq(args.upper);
      expect(await instance.price(args, bidLiq)).to.eq(args.lower);

      args.marketPrice = args.lower;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await instance.price(args, askLiq)).to.eq(args.lower);
      expect(await instance.price(args, bidLiq)).to.eq(args.upper);

      let _average = average(args.lower, args.upper);
      args.marketPrice = _average;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == average(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await instance.price(args, askLiq)).to.eq(_average);
      expect(await instance.price(args, bidLiq)).to.eq(_average);
    });

    it('should revert if price is out of range', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await instance.liquidity(args);

      await expect(
        instance.price(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        instance,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );

      args.isBuy = false;

      await expect(
        instance.price(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        instance,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );
    });
  });

  describe('#nextPrice', () => {
    it('should return upper tick for buy order if liquidity == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.nextPrice(args, 0)).to.eq(args.upper);
    });

    it('should return lower tick for sell order if liquidity == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: 0,
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      expect(await instance.nextPrice(args, 0)).to.eq(args.lower);
    });

    it('should return the price when trade size == 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.5'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      expect(await instance.nextPrice(args, 0)).to.eq(args.marketPrice);

      args.isBuy = false;

      expect(await instance.nextPrice(args, 0)).to.eq(args.marketPrice);
    });

    it('should return the next price for buy order when liquidity > 0 && trade size > 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.25'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await instance.liquidity(args);
      let askLiq = await instance.askLiquidity(args);
      let bidLiq = await instance.bidLiquidity(args);

      // price == lower
      // ask side liquidity == liquidity
      // bid side liquidity == 0

      expect(askLiq).to.eq(liq);
      expect(bidLiq).to.eq(0);

      expect(await instance.nextPrice(args, askLiq)).to.eq(args.upper);

      let _average = average(args.lower, args.upper); // parseEther('0.5')
      expect(await instance.nextPrice(args, askLiq.div(2))).to.eq(_average);

      _average = average(args.lower, _average); // parseEther('0.375')
      expect(await instance.nextPrice(args, askLiq.div(4))).to.eq(_average);

      _average = average(args.lower, args.upper); // parseEther('0.5')
      args.marketPrice = _average;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == average(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await instance.nextPrice(args, askLiq)).to.eq(args.upper);
      expect(await instance.nextPrice(args, bidLiq)).to.eq(args.upper);

      _average = average(args.marketPrice, args.upper); // parseEther('0.625')
      expect(await instance.nextPrice(args, askLiq.div(2))).to.eq(_average);
      expect(await instance.nextPrice(args, bidLiq.div(2))).to.eq(_average);

      _average = average(args.marketPrice, _average); // parseEther('0.5625')
      expect(await instance.nextPrice(args, askLiq.div(4))).to.eq(_average);
      expect(await instance.nextPrice(args, bidLiq.div(4))).to.eq(_average);
    });

    it('should return the next price for sell order when liquidity > 0 && trade size > 0', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'),
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: false,
      };

      let liq = await instance.liquidity(args);
      let askLiq = await instance.askLiquidity(args);
      let bidLiq = await instance.bidLiquidity(args);

      // price == upper
      // ask side liquidity == 0
      // bid side liquidity == liquidity

      expect(askLiq).to.eq(0);
      expect(bidLiq).to.eq(liq);

      expect(await instance.nextPrice(args, bidLiq)).to.eq(args.lower);

      let _average = average(args.lower, args.upper); // parseEther('0.5')
      expect(await instance.nextPrice(args, bidLiq.div(2))).to.eq(_average);

      _average = average(_average, args.upper); // parseEther('0.625')
      expect(await instance.nextPrice(args, bidLiq.div(4))).to.eq(_average);

      _average = average(args.lower, args.upper); // parseEther('0.5')
      args.marketPrice = _average;

      liq = await instance.liquidity(args);
      askLiq = await instance.askLiquidity(args);
      bidLiq = await instance.bidLiquidity(args);

      // price == average(lower, upper)
      // ask side liquidity == liquidity/2
      // bid side liquidity == liquidity/2

      expect(askLiq).to.eq(liq.div(2));
      expect(bidLiq).to.eq(liq.div(2));

      expect(await instance.nextPrice(args, askLiq)).to.eq(args.lower);
      expect(await instance.nextPrice(args, bidLiq)).to.eq(args.lower);

      _average = average(args.lower, args.marketPrice); // parseEther('0.375')
      expect(await instance.nextPrice(args, askLiq.div(2))).to.eq(_average);
      expect(await instance.nextPrice(args, bidLiq.div(2))).to.eq(_average);

      _average = average(_average, args.marketPrice); // parseEther('0.4375')
      expect(await instance.nextPrice(args, askLiq.div(4))).to.eq(_average);
      expect(await instance.nextPrice(args, bidLiq.div(4))).to.eq(_average);
    });

    it('should revert if price is out of range', async () => {
      const { instance } = await loadFixture(deploy);

      let args = {
        liquidityRate: parseEther('1'),
        marketPrice: parseEther('0.75'), // price == upper
        lower: parseEther('0.25'),
        upper: parseEther('0.75'),
        isBuy: true,
      };

      let liq = await instance.liquidity(args);

      await expect(
        instance.nextPrice(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        instance,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );

      args.isBuy = false;

      await expect(
        instance.nextPrice(args, liq.mul(2)),
      ).to.be.revertedWithCustomError(
        instance,
        'Pricing__PriceCannotBeComputedWithinTickRange',
      );
    });
  });
});
