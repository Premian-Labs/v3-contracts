import {OptionMathMock, OptionMathMock__factory} from "../../typechain";
import {expect} from 'chai';
import {ethers} from 'hardhat';
import {formatEther, parseEther} from "ethers/lib/utils";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

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

            for (const t of [
                [parseEther('0.5'), true, '0.095304896963412747'],
                [parseEther('0.8'), true, '0.2524480186054652'],
                [parseEther('1.0'), true, '0.38292492254802624'],
                [parseEther('1.2'), true, '0.5276141806389698'],
                [parseEther('2.2'), true, '1.3691528498675376'],

                [parseEther('0.5'), false, '0.5953050576183792'],
                [parseEther('0.8'), false, '0.45244801860546513'],
                [parseEther('1.0'), false, '0.38292492254802624'],
                [parseEther('1.2'), false, '0.3276141806389699'],
                [parseEther('2.2'), false, '0.16915284986753754'],
            ]) {
                const result = formatEther(
                    await instance.blackScholesPrice(
                        t[0],
                        strike59x18,
                        timeToMaturity59x18,
                        varAnnualized59x18,
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
});