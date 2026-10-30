from pathlib import Path
import copy,sys,unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from css_layout_probe import compare

class CssComparisonTests(unittest.TestCase):
    def value(self):
        box={'x':10,'y':20,'width':100,'height':50}
        return {'ok':True,'html_sha256':'abc','browser_version':'142.0.7444.59',
                'viewport':{'width':1280,'height':713,'dpr':1},'styles':{'radius':'12px'},
                'boxes':{'flex':[box]*3,'grid':[box]*4,'border_box':[box]}}
    def test_equal_geometry_passes(self):
        self.assertTrue(compare(self.value(),self.value())['ok'])
    def test_viewport_mismatch_is_not_accepted(self):
        a=self.value();b=copy.deepcopy(a);b['viewport']['width']=1200
        self.assertFalse(compare(a,b)['ok'])
    def test_missing_boxes_fail(self):
        a=self.value();a['boxes']={};self.assertFalse(compare(a,a)['ok'])
    def test_nan_does_not_hide_difference(self):
        a=self.value();b=copy.deepcopy(a);b['boxes']['grid'][0]['width']=float('nan')
        self.assertFalse(compare(a,b)['ok'])
    def test_two_pixel_displacement_fails(self):
        a=self.value();b=copy.deepcopy(a);b['boxes']['flex'][0]['x']+=2
        self.assertFalse(compare(a,b)['ok'])
    def test_one_failed_css_probe_fails(self):
        a=self.value();b=copy.deepcopy(a);b['ok']=False;self.assertFalse(compare(a,b)['ok'])
if __name__=='__main__':unittest.main(verbosity=2)
