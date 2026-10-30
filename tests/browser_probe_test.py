import importlib.util,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'host'))
from browser_probe import assess_processes

class RoleTests(unittest.TestCase):
    def test_real_roles_are_distinct(self):
        result=assess_processes([{'id':91,'type':'browser'},{'id':171,'type':'renderer'}])
        self.assertTrue(result['ok']);self.assertEqual(result['renderer_pids'],[171])
    def test_unknown_child_not_promoted_to_renderer(self):
        self.assertFalse(assess_processes([{'id':91,'type':'browser'},{'id':171,'type':'zygote'}])['ok'])
    def test_duplicate_pid_is_rejected(self):
        with self.assertRaises(ValueError):assess_processes([{'id':91,'type':'browser'},{'id':91,'type':'renderer'}])
    def test_invalid_pid_is_rejected(self):
        with self.assertRaises(ValueError):assess_processes([{'id':0,'type':'renderer'}])
if __name__=='__main__':unittest.main(verbosity=2)
