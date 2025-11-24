from hashlib import Hasher


struct DefaultTag:
    pass


@fieldwise_init
@register_passable("trivial")
struct Key[Tag: AnyType = DefaultTag](Equatable, Hashable):
    var idx: UInt
    var version: UInt

    fn __eq__(self, other: Self) -> Bool:
        return self.idx == other.idx and self.version == other.version

    fn __hash__[H: Hasher](self, mut hasher: H):
        hasher.update(self.idx)
        hasher.update(self.version)


@fieldwise_init
@register_passable("trivial")
struct Slot:
    # Fields
    var idx_or_free: UInt
    """If the slot is occupied, this is the index into the values array.
        If the slot is free, this is the index of the next free slot."""
    var version: UInt
    """If the version is odd, the slot is occupied.
        If the version is even, the slot is free."""


struct DenseSlotMap[V: Copyable & Movable, Tag: AnyType = DefaultTag](
    Boolable, Copyable, Defaultable, Iterable, Movable, Sized
):
    """A high-performance container with stable unique keys and contiguous storage.

    `DenseSlotMap` is a data structure that combines the cache locality of a
    contiguous array (like `List`) with the safety and stability of generational
    indices. It returns a stable `Key` upon insertion, which can be used to
    retrieve the value later, even if the underlying data has moved in memory
    due to other removals.

    It is ideal for ECS (Entity Component System) architectures, object pools,
    or any scenario where you need safe references to objects that have complex
    lifetimes.

    You can create a `DenseSlotMap` in several ways:

    ```mojo
    # Simple map with default key tag
    var simple_map = DenseSlotMap[Int]()

    # Map with a specific key tag for type safety
    struct MonsterTag: pass
    var monsters = DenseSlotMap[String, MonsterTag]()

    # With pre-allocated capacity (future implementation)
    # var preallocated = DenseSlotMap[Float64](capacity=100)
    ```

    Be aware of the following characteristics:

    - **Stable Keys & Versioning**: Unlike a `List` where indices shift when
      elements are removed, keys issued by `DenseSlotMap` are stable. If you
      remove an element, its key becomes invalid. The map uses "generational
      indices" (a version number in the key) to detect use-after-free errors
      safely.

      ```mojo
      var map = DenseSlotMap[String]()
      var key = map.insert("Hero")
      map.pop(key)
      var val = map.get(key)   # Returns None (Safe!)
      ```

    - **Contiguous Memory (Dense)**: Values are stored in a contiguous `List`,
      ensuring high cache locality during iteration. When an item is removed,
      the last item in the list is moved to fill the gap ("swap-and-pop").
      This means **iteration order is not preserved** across removals.

    - **Type Safety with Tags**: You can use the `Tag` parameter to create
      distinct key types for different maps, preventing logical errors at compile
      time.

      ```mojo
      struct PlayerTag: pass
      struct EnemyTag: pass

      var players = DenseSlotMap[Int, PlayerTag]()
      var enemies = DenseSlotMap[Int, EnemyTag]()

      var p_key = players.insert(1)
      # var e_val = enemies[p_key]  # Compile Error! Key type mismatch.
      ```

    - **Reference Access**: The `[]` operator returns a mutable reference (`ref`)
      to the stored value, allowing direct modification without copying or
      re-insertion.

      ```mojo
      var map = DenseSlotMap[Int]()
      var key = map.insert(10)
      map[key] += 5  # Direct in-place modification
      ```

    - **Value Semantics**: Like `List`, `DenseSlotMap` is value semantic. Assignment
      creates a deep copy of all keys, values, and internal slots.

    Examples:

    ```mojo
    var sm = DenseSlotMap[String]()

    # Insert elements
    var k1 = sm.insert("Apple")
    var k2 = sm.insert("Banana")

    # Access elements
    print(sm.get(k1).value())    # "Apple" (Safe access via Optional)
    print(sm[k1])                # "Apple" (Direct access via Reference)

    # Modify elements in-place
    sm[k1] = "Apricot"

    # Remove elements
    var removed = sm.pop(k1)     # Removes "Apricot", k1 is now invalid
    if not sm.get(k1):
        print("Key is expired")

    # Iterate over values (Fast contiguous iteration)
    # Note: Order is arbitrary after removals due to swap-and-pop
    for fruit in sm:
        print(fruit)

    # Map properties
    print('len:', len(sm))       # Current number of elements

    # Clear map (invalidates all existing keys)
    sm.clear()
    ```
    """

    var keys: List[Key[Self.Tag]]
    """The keys corresponding to each value in the values array."""
    var values: List[Self.V]
    """The actual values stored in the slot map."""
    var slots: List[Slot]
    """The sparse array of slots. Maps keys to indices in the values array."""
    var free_head: UInt
    """The index of the first free slot in the slots array."""

    comptime IteratorType[
        iterable_mut: Bool, //, iterable_origin: Origin[iterable_mut]
    ]: Iterator = List[Self.V].IteratorType[iterable_origin]

    fn __init__(out self):
        self.keys = List[Key[Self.Tag]]()
        self.values = List[Self.V]()
        self.slots = List[Slot]()
        self.slots.append(Slot(0, 0))
        self.free_head = 1

    fn __init__(out self, *, capacity: Int):
        self.keys = List[Key[Self.Tag]](capacity=capacity)
        self.values = List[Self.V](capacity=capacity)
        self.slots = List[Slot](capacity=capacity + 1)
        self.slots.append(Slot(0, 0))
        self.free_head = 1

    fn __len__(self) -> Int:
        return self.keys.__len__()

    fn __bool__(self) -> Bool:
        return self.__len__().__bool__()

    fn insert(mut self, var value: Self.V) -> Key[Self.Tag]:
        self.values.append(value^)
        var value_idx = UInt(len(self.values) - 1)

        if self.free_head < UInt(len(self.slots)):
            # Reuse a free slot
            var slot_idx = self.free_head
            var slot = self.slots[slot_idx]

            self.free_head = slot.idx_or_free

            var new_version = slot.version
            if new_version % 2 == 0:
                new_version += 1
            self.slots[slot_idx] = Slot(value_idx, new_version)

            var key = Key[Self.Tag](slot_idx, new_version)
            self.keys.append(key)
            return key
        else:
            # Create a new slot
            var slot_idx = UInt(len(self.slots))
            var version: UInt = 1
            self.slots.append(Slot(value_idx, version))

            self.free_head = slot_idx + 1

            var key = Key[Self.Tag](slot_idx, version)
            self.keys.append(key)
            return key

    fn get(self, key: Key[Self.Tag]) -> Optional[Self.V]:
        try:
            return self._find_ref(key).copy()
        except:
            return None

    fn pop(mut self, key: Key[Self.Tag]) -> Optional[Self.V]:
        var slot_idx = key.idx
        if Int(slot_idx) >= len(self.slots):
            return None

        var slot = self.slots[slot_idx]
        if slot.version != key.version:
            return None

        var value_idx = slot.idx_or_free

        # Mark the slot as free
        self.slots[slot_idx].version += 1
        self.slots[slot_idx].idx_or_free = self.free_head
        self.free_head = slot_idx

        # Swap-remove the value
        if Int(value_idx) == len(self.values) - 1:
            _ = self.keys.pop()
            return self.values.pop()

        var last_val = self.values.pop()
        var last_key = self.keys.pop()
        var last_slot_idx = last_key.idx

        var removed_val = self.values[value_idx].copy()
        self.values[value_idx] = last_val^
        self.keys[value_idx] = last_key

        # Update the slot that points to the moved value
        self.slots[last_slot_idx].idx_or_free = value_idx

        return removed_val^

    fn __iter__(ref self) -> Self.IteratorType[origin_of(self)]:
        return rebind[Self.IteratorType[origin_of(self)]](
            Self.IteratorType[origin_of(self.values)](
                0, Pointer(to=self.values)
            )
        )

    fn __getitem__(ref self, key: Key) raises -> ref [self.values] Self.V:
        return self._find_ref(key)

    fn _find_ref(ref self, key: Key) raises -> ref [self.values] Self.V:
        var slot_idx = Int(key.idx)
        if slot_idx >= len(self.slots):
            raise Error("KeyError")

        var slot = self.slots[slot_idx]
        if slot.version != key.version:
            raise Error("KeyError")

        var value_idx = slot.idx_or_free
        return self.values[value_idx]

    fn __contains__(self, key: Key[Self.Tag]) -> Bool:
        var slot_idx = Int(key.idx)
        if slot_idx >= len(self.slots):
            return False

        ref slot = self.slots[slot_idx]
        return slot.version == key.version

    fn clear(mut self):
        self.keys.clear()
        self.values.clear()
        self.free_head = 1

        for i in range(1, len(self.slots)):
            var current_version = self.slots[i].version
            if current_version % 2 == 1:
                self.slots[i].version = current_version + 1
            self.slots[i].idx_or_free = UInt(i + 1)
