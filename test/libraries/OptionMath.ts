import {OptionMathMock, OptionMathMock__factory, PositionMock__factory} from "../../typechain";
import { expect } from 'chai';
import { ethers } from 'hardhat';
import {formatEther, parseEther} from "ethers/lib/utils";
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

describe('OptionMath', () => {
    let deployer: SignerWithAddress;
    let instance: OptionMathMock;

    before(async function () {
        [deployer] = await ethers.getSigners();
        instance = await new OptionMathMock__factory(deployer).deploy();
    });

    it('test of the normal CDF approximation helper. should equal the expected value', async () => {
        for (const t of [
            [parseEther('-3.0'), parseEther('0.997937931253017293')],
            [parseEther('-2.'), parseEther('0.972787315787072559')],
            [parseEther('-1.'), parseEther('0.836009939237039072')],
            [parseEther('0.'), parseEther('0.5')],
            [parseEther('1.'), parseEther('0.153320858106603138')],
            [parseEther('2.'), parseEther('0.018287098844188538')],
            [parseEther('3.'), parseEther('0.000638104717830912')],
        ]) {
            expect(formatEther(await instance.helperNormal(t[0]))).to.eq(formatEther(t[1]));
        }
    });

    it('test of the normal CDF approximation. should equal the expected value', async () => {
        for (const t of [
            [parseEther('-3.0'), parseEther('0.001350086732406809')],
            [parseEther('-2.'), parseEther('0.022749891528557989')],
            [parseEther('-1.'), parseEther('0.158655459434782033')],
            [parseEther('0.'), parseEther('0.5')],
            [parseEther('1.'), parseEther('0.841344540565217967')],
            [parseEther('2.'), parseEther('0.977250108471442010')],
            [parseEther('3.'), parseEther('0.998649913267593190')],
        ]) {
            expect(formatEther(await instance.normalCdf(t[0]))).to.eq(formatEther(t[1]));
        }
    });
});