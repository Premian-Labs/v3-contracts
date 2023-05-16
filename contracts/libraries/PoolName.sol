// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {BokkyPooBahsDateTimeLibrary as DateTime} from "@bokkypoobah/BokkyPooBahsDateTimeLibrary.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";

import {WAD} from "./Constants.sol";

library PoolName {
    using UintUtils for uint256;

    function name(
        address base,
        address quote,
        uint256 maturity,
        uint256 strike,
        bool isCallPool
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    IERC20Metadata(base).symbol(),
                    "-",
                    IERC20Metadata(quote).symbol(),
                    "-",
                    maturityToString(maturity),
                    "-",
                    strikeToString(strike),
                    "-",
                    isCallPool ? "C" : "P"
                )
            );
    }

    function strikeToString(
        uint256 strike
    ) internal pure returns (string memory) {
        bytes memory strikeBytes;
        if (strike >= WAD) {
            strikeBytes = abi.encodePacked((strike / WAD).toString());

            strike = ((strike * 100) / WAD) % 100;
            if (strike > 0) {
                if (strike % 10 == 0) {
                    strikeBytes = abi.encodePacked(
                        strikeBytes,
                        ".",
                        (strike / 10).toString()
                    );
                } else {
                    strikeBytes = abi.encodePacked(
                        strikeBytes,
                        ".",
                        strike < 10 ? "0" : "",
                        strike.toString()
                    );
                }
            }
        } else {
            strikeBytes = abi.encodePacked("0.");
            strike *= 10;

            while (strike < WAD) {
                strikeBytes = abi.encodePacked(strikeBytes, "0");
                strike *= 10;
            }

            strikeBytes = abi.encodePacked(
                strikeBytes,
                (strike / WAD).toString()
            );

            uint256 lastDecimal = (strike * 10) / WAD - (strike / WAD) * 10;
            if (lastDecimal != 0) {
                strikeBytes = abi.encodePacked(
                    strikeBytes,
                    lastDecimal.toString()
                );
            }
        }

        return string(strikeBytes);
    }

    function maturityToString(
        uint256 maturity
    ) internal pure returns (string memory) {
        (uint256 year, uint256 month, uint256 day) = DateTime.timestampToDate(
            maturity
        );

        return
            string(
                abi.encodePacked(
                    day < 10 ? "0" : "",
                    day.toString(),
                    monthToString(month),
                    year.toString()
                )
            );
    }

    function monthToString(
        uint256 month
    ) internal pure returns (string memory) {
        if (month == 1) return "JAN";
        if (month == 2) return "FEB";
        if (month == 3) return "MAR";
        if (month == 4) return "APR";
        if (month == 5) return "MAY";
        if (month == 6) return "JUN";
        if (month == 7) return "JUL";
        if (month == 8) return "AUG";
        if (month == 9) return "SEP";
        if (month == 10) return "OCT";
        if (month == 11) return "NOV";
        if (month == 12) return "DEC";

        revert();
    }
}
