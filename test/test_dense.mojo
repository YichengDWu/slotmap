from slotmap import DenseSlotMap, Key
from testing import (
    assert_equal,
    assert_false,
    assert_raises,
    assert_true,
    TestSuite,
)

struct MyTag:
    pass


def test_construction():
    _ = DenseSlotMap[Int]()
    _ = DenseSlotMap[Int, MyTag]()

def test_basic():
    var sm: DenseSlotMap[Int] = {}
    var k1 = sm.insert(10)
    var k2 = sm.insert(20)

    assert_equal(sm[k1], 10)
    assert_equal(sm[k2], 20)

def test_bool_conversion():
    var sm: DenseSlotMap[Int] = {}
    assert_false(sm)

    var k1 = sm.insert(42)
    var k2 = sm.insert(84)
    assert_true(sm)
    _ = sm.pop(k1)
    assert_true(sm)
    _ = sm.pop(k2)
    assert_false(sm)

def test_compact():
    var sm: DenseSlotMap[String] = {}
    var keys = List[Key]()
    for i in range(10):
        keys.append(sm.insert(String(i)))
    for key in keys:
        _ = sm.pop(key)
    assert_equal(len(sm.values), 0)

def test_iter():
    var sm: DenseSlotMap[Int] = {}
    var expected = List[Int]()
    for i in range(5):
        _ = sm.insert(i * 3)
        expected.append(i * 3)

    var actual = List[Int]()
    for value in sm:
        actual.append(value)

    assert_equal(actual, expected)

def test_iter_mut():
    var sm: DenseSlotMap[Int] = {}
    for i in range(5):
        _ = sm.insert(i * 2)

    for ref value in sm:
        value += 1

    var expected = List[Int]()
    for i in range(5):
        expected.append(i * 2 + 1)

    var actual = List[Int]()
    for value in sm:
        actual.append(value)

    assert_equal(actual, expected)

def test_copy():
    var orig: DenseSlotMap[String] = {}
    var k1 = orig.insert("a")

    var copy = orig.copy()
    assert_equal(copy[k1], "a")

    copy[k1] = "b"
    assert_equal(orig[k1], "a")
    assert_equal(copy[k1], "b")
    
def test_clear():
    var sm: DenseSlotMap[Int] = {}
    var k1 = sm.insert(1)
    var k2 = sm.insert(2)
    assert_equal(len(sm), 2)

    sm.clear()
    assert_equal(len(sm), 0)
    _ = sm.insert(1)
    _ = sm.insert(2)
    assert_false(k1 in sm)
    assert_false(k2 in sm)

def main():
    TestSuite.discover_tests[__functions_in_module()]().run()