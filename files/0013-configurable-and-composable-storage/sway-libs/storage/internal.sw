//! This module contains functions for low-level storage access.
//! These functions should be used only when developing a custom
//! [Storage] and should never occur in a contract code.

// TODO-DISCUSSION: See the comment on `Serializable` in the `storage_box.sw`.
use core::marker::Serializable;

#[storage(write)]
pub fn write<T>(storage_key: &StorageKey, value: &T)
where T: Serializable
{
    //--
    // Here comes the same implementation as in the current `std::storage::storage_api::write`.
    //--
}

#[storage(read)]
pub fn read<T>(storage_key: &StorageKey) -> Option<T>
    where T: Serializable 
{ 
    //--
    // Here comes the same implementation as in the current `std::storage::storage_api::read`.
    //--
}

//--
// TODO-DISCUSSION: Should we also provide a function for clearing a certain number of elements of
//                  the type `T`? This would, e.g., easy clearing a known number of bytes.
//                  Also a dedicated function for clearing the slot, e.g., `clear_slot(<key>)`.
//--
#[storage(write)]
pub fn clear<T>(storage_key: &StorageKey) -> bool
    where T: Serializable 
{
    //--
    // Here comes the same implementation as in the current `std::storage::storage_api::clear`.
    //--
}
