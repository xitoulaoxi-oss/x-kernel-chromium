from pathlib import Path
import json,subprocess,sys,tempfile,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from process_identity_check import assess,parse_snapshot

class IdentityTests(unittest.TestCase):
    def snapshot(self):
        return parse_snapshot('PROC_IDENTITY_PID=91\nPid:\t91\nPPid:\t1\nThreads:\t8\nPROC_IDENTITY_PID=126\nPid:\t126\nPPid:\t91\nThreads:\t1\nPROC_IDENTITY_PID=171\nPid:\t171\nPPid:\t126\nThreads:\t9\n')
    def test_renderer_joins_through_zygote(self):
        self.assertTrue(assess({'ok':True,'browser_pids':[91],'renderer_pids':[171]},self.snapshot())['ok'])
    def test_unknown_child_is_not_role_proof(self):
        self.assertFalse(assess({'ok':True,'browser_pids':[91],'renderer_pids':[]},self.snapshot())['ok'])
    def test_unrelated_renderer_is_rejected(self):
        s=self.snapshot();s[171]['PPid']=1
        self.assertFalse(assess({'ok':True,'browser_pids':[91],'renderer_pids':[171]},s)['ok'])
    def test_zombie_renderer_is_rejected(self):
        s=self.snapshot();s[171]['State']='Z (zombie)'
        self.assertFalse(assess({'ok':True,'browser_pids':[91],'renderer_pids':[171]},s)['ok'])
    def test_zero_thread_renderer_is_rejected(self):
        s=self.snapshot();s[171]['Threads']=0
        self.assertFalse(assess({'ok':True,'browser_pids':[91],'renderer_pids':[171]},s)['ok'])
    def test_zombie_browser_is_rejected(self):
        s=self.snapshot();s[91]['State']='X (dead)'
        self.assertFalse(assess({'ok':True,'browser_pids':[91],'renderer_pids':[171]},s)['ok'])
    def test_echoed_script_is_not_a_snapshot(self):
        self.assertEqual(parse_snapshot('echo "PROC_IDENTITY_PID=$p"\ngrep Pid /proc/$p/status'),{})
    def test_missing_evidence_is_structured_failure(self):
        root=Path(__file__).resolve().parents[1]
        fixtures=root/'experiments/REVIEW-FIX'
        fixtures.mkdir(parents=True,exist_ok=True)
        session=tempfile.mkdtemp(prefix='identity-missing-',dir=fixtures)
        tool=root/'host/process_identity_check.py'
        result=subprocess.run([sys.executable,str(tool),session],capture_output=True,text=True)
        self.assertEqual(result.returncode,1)
        self.assertFalse(json.loads(result.stdout)['ok'])
        self.assertEqual(result.stderr,'')
if __name__=='__main__':unittest.main(verbosity=2)
