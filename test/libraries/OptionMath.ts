import { expect } from 'chai';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { OptionMathMock, OptionMathMock__factory } from '../../typechain';
import { formatEther, parseEther } from 'ethers/lib/utils';
import { now } from '../../utils/time';

describe('OptionMath', () => {
    let deployer: SignerWithAddress;
    let instance: OptionMathMock;

    before(async function () {
        [deployer] = await ethers.getSigners();
        instance = await new OptionMathMock__factory(deployer).deploy();
    });

    describe('#helperNormal', function () {
        it('test of the normal CDF approximation helper. should equal the expected value', async () => {
            for (const t of [
                [parseEther('-3.0'), '0.997937931253017293'],
                [parseEther('-2.'), '0.972787315787072559'],
                [parseEther('-1.'), '0.836009939237039072'],
                [parseEther('0.'), '0.5'],
                [parseEther('1.'), '0.153320858106603138'],
                [parseEther('2.'), '0.018287098844188538'],
                [parseEther('3.'), '0.000638104717830912'],
            ]) {
                expect(formatEther(await instance.helperNormal(t[0]))).to.eq(t[1]);
            }
        });
    });

    describe('#normalCDF', function () {
        it('test of the normal CDF approximation. should equal the expected value', async () => {
            for (const t of [
                [parseEther('-3.0'), '0.001350086732406809'],
                [parseEther('-2.'), '0.022749891528557989'],
                [parseEther('-1.'), '0.158655459434782033'],
                [parseEther('0.'), '0.5'],
                [parseEther('1.'), '0.841344540565217967'],
                [parseEther('2.'), '0.97725010847144201'],
                [parseEther('3.'), '0.99864991326759319'],
            ]) {
                expect(formatEther(await instance.normalCdf(t[0]))).to.eq(t[1]);
            }
        });
    });

    describe('#relu', function () {
        it('test of the relu function. should equal the expected value', async () => {
            for (const t of [
                [parseEther('-3.6'), '0.'],
                [parseEther('-2.2'), '0.'],
                [parseEther('-1.1'), '0.'],
                [parseEther('0.'), '0.'],
                [parseEther('1.1'), '1.1'],
                [parseEther('2.1'), '2.1'],
                [parseEther('3.6'), '3.6'],
            ]) {
                expect(parseFloat(formatEther(await instance.relu(t[0])))).to.eq(parseFloat(t[1]));
            }
        });
    });
    describe('#blackScholesPrice', function () {
        it('test of the Black-Scholes formula when variance is zero', async () => {
            const strike59x18 = parseEther('1.');
            const timeToMaturity59x18 = parseEther('1.');
            const varAnnualized59x18 = parseEther('0.');
            const riskFreeRate59x18 = parseEther('0.');

            for (const t of [
                [parseEther('0.5'), true, '0.0'],
                [parseEther('0.8'), true, '0.0'],
                [parseEther('1.0'), true, '0.0'],
                [parseEther('1.2'), true, '0.2'],
                [parseEther('2.2'), true, '1.2'],

                [parseEther('0.5'), false, '0.5'],
                [parseEther('0.8'), false, '0.2'],
                [parseEther('1.0'), false, '0.0'],
                [parseEther('1.2'), false, '0.0'],
                [parseEther('2.2'), false, '0.0'],

            ]) {
                const result = formatEther(
                    await instance.blackScholesPrice(
                        t[0],
                        strike59x18,
                        timeToMaturity59x18,
                        varAnnualized59x18,
                        riskFreeRate59x18,
                        t[1]
                    )
                );
                expect(parseFloat(result)).to.eq(parseFloat(t[2]));
            }
        });

        it('test of the Black-Scholes formula', async () => {
            const strike59x18 = parseEther('1.');
            const timeToMaturity59x18 = parseEther('1.');
            const varAnnualized59x18 = parseEther('1.');
            const riskFreeRate59x18 = parseEther('0.1');

            for (const t of [
                [parseEther('0.5'), true, '0.10733500381254471'],
                [parseEther('0.8'), true, '0.27626266618753637'],
                [parseEther('1.0'), true, '0.4139595806172845'],
                [parseEther('1.2'), true, '0.5651268636770026'],
                [parseEther('2.2'), true, '1.4293073801560254'],

                [parseEther('0.5'), false, '0.5121724218485042'],
                [parseEther('0.8'), false, '0.3811000842234958'],
                [parseEther('1.0'), false, '0.3187969986532439'],
                [parseEther('1.2'), false, '0.26996428171296216'],
                [parseEther('2.2'), false, '0.13414479819198477'],
            ]) {
                const result = formatEther(
                    await instance.blackScholesPrice(
                        t[0],
                        strike59x18,
                        timeToMaturity59x18,
                        varAnnualized59x18,
                        riskFreeRate59x18,
                        t[1]
                    )
                );
                expect(
                    parseFloat(result) - parseFloat(t[2])
                ).to.be.closeTo(
                    0., 0.000001
                );
            }
        });
    });
  describe('isFriday', () => {
    describe('should return false', () => {
      it('if maturity is Mon (08:00:00)', async () => {
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

  describe('isLastFriday', () => {
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

  describe('calculateTimeToMaturity', () => {
    it('should return the time until maturity', async () => {
      const _now = await now();
      expect(await instance.calculateTimeToMaturity(_now + 86400)).to.eq(86400);
    });
  });

  describe('calculateStrikeInterval', () => {
    it('should return 0.1 between 1 and 4', async () => {
      for (let x of [
        [1, 0.1],
        [2, 0.1],
        [3, 0.1],
        [4, 0.1],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 0.5 between 5 and 9', async () => {
      for (let x of [
        [5, 0.5],
        [6, 0.5],
        [7, 0.5],
        [9, 0.5],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 1 between 10 and 49', async () => {
      for (let x of [
        [10, 1],
        [11, 1],
        [33, 1],
        [49, 1],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 5 between 50 and 99', async () => {
      for (let x of [
        [50, 5],
        [51, 5],
        [74, 5],
        [99, 5],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 10 between 100 and 499', async () => {
      for (let x of [
        [100, 10],
        [101, 10],
        [434, 10],
        [499, 10],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 50 between 500 and 999', async () => {
      for (let x of [
        [500, 50],
        [501, 50],
        [871, 50],
        [999, 50],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 100 between 1000 and 4999', async () => {
      for (let x of [
        [1000, 100],
        [1001, 100],
        [4356, 100],
        [4999, 100],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
      }
    });

    it('should return 500 between 5000 and 9999', async () => {
      for (let x of [
        [5000, 500],
        [5001, 500],
        [5643, 500],
        [9999, 500],
      ]) {
        let strike = parseEther(x[0].toString());
        let interval = await instance.calculateStrikeInterval(strike);

        expect(interval).to.eq(parseEther(x[1].toString()));
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




