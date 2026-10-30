from pathlib import Path
import sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from perf_run import assess_collection,METRIC_DEFS

class PerfAssessmentTests(unittest.TestCase):
    def test_five_legacy_samples_do_not_qualify(self):
        result=assess_collection([{'run':i,'harness_rc':0,'renderer_s':10,'peak_mem_mb':800,'first_frame_s':20} for i in range(5)])
        self.assertTrue(result['collection_ok'])
        self.assertFalse(result['qualified'])
        self.assertEqual(result['finals_four_metric_gate'],'BLOCKED')
    def test_failed_child_cannot_be_ignored(self):
        result=assess_collection([{'run':1,'harness_rc':1}])
        self.assertFalse(result['collection_ok']);self.assertEqual(result['failed_or_unknown_runs'],[1])
    def test_missing_exit_status_is_unknown(self):
        self.assertFalse(assess_collection([{'run':1}])['collection_ok'])
    def test_no_runs_is_not_success(self):
        self.assertFalse(assess_collection([])['collection_ok'])
    def test_host_memory_and_renderer_heuristic_are_labelled(self):
        self.assertEqual(METRIC_DEFS['renderer_s']['class'],'counter')
        self.assertEqual(METRIC_DEFS['peak_mem_mb']['class'],'host-qemu-memory')
if __name__=='__main__':unittest.main(verbosity=2)
