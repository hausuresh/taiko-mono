// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import { AddressResolver } from "../contracts/common/AddressResolver.sol";
import { EtherVault } from "../contracts/bridge/EtherVault.sol";
import { IBridge } from "../contracts/bridge/IBridge.sol";
import { LibBridgeData } from "../contracts/bridge/libs/LibBridgeData.sol";
import { LibBridgeStatus } from "../contracts/bridge/libs/LibBridgeStatus.sol";

interface VaultContract {
    function releaseToken(IBridge.Message calldata message) external;
}

/**
 * This library provides functions for releasing Ether related to message
 * execution on the Bridge.
 */
library LibBridgeRelease {
    /// @notice: A mock contract which returns always 'true' for isMessageFailed
    using LibBridgeData for IBridge.Message;

    event EtherReleased(bytes32 indexed msgHash, address to, uint256 amount);

    error B_ETHER_RELEASED_ALREADY();
    error B_FAILED_TRANSFER();
    error B_MSG_NOT_FAILED();
    error B_OWNER_IS_NULL();
    error B_WRONG_CHAIN_ID();

    /**
     * Release Ether to the message owner
     * @dev This function releases Ether to the message owner, only if the
     * Bridge state says:
     * - Ether for this message has not been released before.
     * - The message is in a failed state.
     * @param state The current state of the Bridge
     * @param resolver The AddressResolver instance
     * @param message The message whose associated Ether should be released
     * @param proof The proof data
     */
    function recallMessage(
        LibBridgeData.State storage state,
        AddressResolver resolver,
        IBridge.Message calldata message,
        bytes calldata proof
    )
        internal
    {
        if (message.owner == address(0)) {
            revert B_OWNER_IS_NULL();
        }

        if (message.srcChainId != block.chainid) {
            revert B_WRONG_CHAIN_ID();
        }

        bytes32 msgHash = message.hashMessage();

        if (state.msgReleased[msgHash] == true) {
            revert B_ETHER_RELEASED_ALREADY(); //Rather tokens released (?)
        }

        ///////////////////////////
        //  Mock to avoid valid  //
        //  proofs.This part is  //
        //  already tested in    //
        //  in other tests with  //
        //  valid proofs.        //
        ///////////////////////////
        if (false) {
            revert B_MSG_NOT_FAILED();
        }

        state.msgReleased[msgHash] = true;

        uint256 releaseAmount = message.depositValue + message.callValue;

        if (releaseAmount > 0) {
            address ethVault = resolver.resolve("ether_vault", true);
            // if on Taiko
            if (ethVault != address(0)) {
                EtherVault(payable(ethVault)).releaseEther(
                    message.owner, releaseAmount
                );
            } else {
                // if on Ethereum
                (bool success,) = message.owner.call{ value: releaseAmount }("");
                if (!success) {
                    revert B_FAILED_TRANSFER();
                }
            }
        }

        // Now try to process message.data via calling the releaseToken() on
        // the proper vault
        if (
            message.to
                == AddressResolver(address(this)).resolve(
                    message.destChainId, "erc20_vault", false
                )
        ) {
            VaultContract(
                AddressResolver(address(this)).resolve(
                    message.srcChainId, "erc20_vault", false
                )
            ).releaseToken(message);
        } else if (
            message.to
                == AddressResolver(address(this)).resolve(
                    message.destChainId, "erc721_vault", false
                )
        ) {
            VaultContract(
                AddressResolver(address(this)).resolve(
                    message.srcChainId, "erc721_vault", false
                )
            ).releaseToken(message);
        } else if (
            message.to
                == AddressResolver(address(this)).resolve(
                    message.destChainId, "erc1155_vault", false
                )
        ) {
            VaultContract(
                AddressResolver(address(this)).resolve(
                    message.srcChainId, "erc1155_vault", false
                )
            ).releaseToken(message);
        }

        emit EtherReleased(msgHash, message.owner, releaseAmount);
    }
}
