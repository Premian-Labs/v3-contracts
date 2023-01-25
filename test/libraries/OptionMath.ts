import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { parseEther } from 'ethers/lib/utils';
import { now } from '../../utils/time';

describe('OptionMath', () => {
  let deployer: SignerWithAddress;
  let instance: OptionMathMock;

  before(async function () {
    [deployer] = await ethers.getSigners();
    instance = await new OptionMathMock__factory(deployer).deploy();
  });

  describe('isFriday(uint64)', () => {
    describe('should return false', () => {
      it(' if maturity is Mon', async () => {
        // Mon Jan 23 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674460800)).is.false;
      });

      it('if maturity is Tue (08:00:00)', async () => {
        // Tue Jan 24 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674547200)).is.false;
      });

      it('if maturity is Wed (08:00:00)', async () => {
        // Wed Jan 25 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674720000)).is.false;
      });

      it('if maturity is Thu (08:00:00)', async () => {
        // Thu Jan 26 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674633600)).is.false;
      });

      it('if maturity is Thu (23:59:59)', async () => {
        // Thu Jan 26 2023 23:59:59 GMT+0000
        expect(await instance.isFriday(1674777599)).is.false;
      });

      it('if maturity is Sat (00:00:00)', async () => {
        // Sat Jan 28 2023 00:00:00 GMT+0000
        expect(await instance.isFriday(1674864000)).is.false;
      });

      it('if maturity is Sat (08:00:00)', async () => {
        // Sat Jan 28 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674892800)).is.false;
      });

      it('if maturity is Sun (08:00:00)', async () => {
        // Sun Jan 29 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674979200)).is.false;
      });
    });
    describe('should return true', () => {
      it('if maturity is Fri (00:00:00)', async () => {
        // Fri Jan 27 2023 00:00:00 GMT+0000
        expect(await instance.isFriday(1674777600)).is.true;
      });

      it('if maturity is Fri (08:00:00)', async () => {
        // Fri Jan 27 2023 08:00:00 GMT+0000
        expect(await instance.isFriday(1674806400)).is.true;
      });

      it('if maturity is Fri (23:59:59)', async () => {
        // Fri Jan 27 2023 23:59:59 GMT+0000
        expect(await instance.isFriday(1674863999)).is.true;
      });
    });
  });

  describe('isLastFriday(uint64)', () => {
    describe('should return false', () => {
      it('if first week of month', async () => {
        // Thu Feb 02 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1675324800)).is.false;
        // Fri Feb 03 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1675411200)).is.false;
      });

      it('if second week of month', async () => {
        // Mon Feb 06 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1675670400)).is.false;
        // Fri Feb 10 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1676016000)).is.false;
      });

      it('if third week of month', async () => {
        // Fri Feb 17 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1676620800)).is.false;
        // Sat Feb 18 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1676707200)).is.false;
      });

      it('if last week of month and day is not Friday (28-day month)', async () => {
        // Thu Feb 23 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1677139200)).is.false;
        // Sat Feb 25 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1677312000)).is.false;
        // Tue Feb 28 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1677571200)).is.false;
      });

      it('if last week of month and day is not Friday (30-day month)', async () => {
        // Mon Sep 25 2023 07:00:00 GMT+0000
        expect(await instance.isLastFriday(1695625200)).is.false;
        // Wed Sep 27 2023 07:00:00 GMT+0000
        expect(await instance.isLastFriday(1695798000)).is.false;
        // Sat Sep 30 2023 07:00:00 GMT+0000
        expect(await instance.isLastFriday(1696057200)).is.false;
      });

      it('if last week of month and day is not Friday (31-day month)', async () => {
        // Mon Dec 23 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1703491200)).is.false;
        // Thu Dec 28 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1703750400)).is.false;
        // Sun Dec 31 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1704009600)).is.false;
      });
    });

    describe('should return true', () => {
      it('if last week of month and day is Friday (28-day month)', async () => {
        // Fri Feb 24 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1677225600)).is.true;
      });

      it('if last week of month and day is Friday (30-day month)', async () => {
        // Fri Sep 29 2023 07:00:00 GMT+0000
        expect(await instance.isLastFriday(1695970800)).is.true;
      });

      it('if last week of month and day is Friday (31-day month)', async () => {
        // Fri Dec 29 2023 08:00:00 GMT+0000
        expect(await instance.isLastFriday(1703836800)).is.true;
      });
    });
  });

  describe('calculateTimeToMaturity(uint64)', () => {
    it('should return the time until maturity', async () => {
      const _now = await now();
      expect(await instance.calculateTimeToMaturity(_now + 86400)).to.eq(86400);
    });
  });

  describe('calculateStrikeInterval(int256)', () => {
    it('should return correct strike interval between 1E18 and 9999E18', async () => {
      let strike = parseEther('1');
      let increment = strike;

      let interval = strike.div(10);
      let limit = parseEther('9999');

      while (strike.lte(limit)) {
        let y = await instance.calculateStrikeInterval(strike);

        if (strike.lt(interval.mul(50))) {
          expect(y).to.eq(interval);
        } else {
          expect(y).to.eq(interval.mul(5));
        }

        strike = strike.add(increment);

        if (strike.eq(interval.mul(100))) {
          interval = interval.mul(10);
        }
      }
    });

    it('should return 1000 between 10000 and 49999', async () => {
      for (let x of [
        [10000, 1000],
        [10001, 1000],
        [35321, 1000],
        [49999, 1000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 5000 between 50000 and 99999', async () => {
      for (let x of [
        [50000, 5000],
        [50001, 5000],
        [64312, 5000],
        [99999, 5000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 10000 between 100000 and 499999', async () => {
      for (let x of [
        [100000, 10000],
        [100001, 10000],
        [256110, 10000],
        [499999, 10000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 50000 between 500000 and 999999', async () => {
      for (let x of [
        [500000, 50000],
        [500001, 50000],
        [862841, 50000],
        [999999, 50000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 100000 between 1000000 and 4999999', async () => {
      for (let x of [
        [1000000, 100000],
        [1000001, 100000],
        [4321854, 100000],
        [4999999, 100000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 500000 between 5000000 and 9999999', async () => {
      for (let x of [
        [5000000, 500000],
        [5000001, 500000],
        [9418355, 500000],
        [9999999, 500000],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });
  });
});
