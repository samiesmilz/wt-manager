import tempfile, unittest, json
from unittest.mock import patch
import wtmanager as T

class ClosedPRHistory(unittest.TestCase):
    def run_lookup(self, rows, head='current', rc=0):
        w=T.Worktree(repo='repo',path='/tmp/tree',branch='feature',primary=False,base='main',base_source='pr')
        with tempfile.TemporaryDirectory() as d, patch.object(T,'cache_dir',return_value=T.Path(d)), patch.object(T,'have',return_value=True), patch.object(T,'repo_facts',return_value=('','https://github.com/example/repo')), patch.object(T,'known_unseen',return_value=False), patch.object(T,'gh_json',return_value=(rc,json.dumps(rows),'failed',None)), patch.object(T,'git',return_value=(0,head,'')):
            T.attach_closed_pr(w,'gitdir','workdir',ttl=0)
        return w
    def test_exact_closed_commit_is_attached_without_claiming_it_landed(self):
        w=self.run_lookup([{'number':7,'state':'CLOSED','headRefOid':'current','url':'https://github.com/example/repo/pull/7','author':None}])
        self.assertEqual(w.pr.state,'CLOSED');self.assertFalse(w.landed)
    def test_reused_branch_and_merged_history_cannot_be_mislabeled_closed(self):
        self.assertIsNone(self.run_lookup([{'number':7,'state':'CLOSED','headRefOid':'old'}]).pr)
        self.assertIsNone(self.run_lookup([{'number':7,'state':'MERGED','headRefOid':'current'}]).pr)
    def test_failed_or_partial_provider_data_is_not_an_empty_success(self):
        before=len(T.NOTICES)
        self.assertIsNone(self.run_lookup([],rc=1).pr)
        self.assertGreater(len(T.NOTICES),before)
        before=len(T.NOTICES)
        self.assertIsNone(self.run_lookup({'invalid':'object'}).pr)
        self.assertGreater(len(T.NOTICES),before)

class MergedActivity(unittest.TestCase):
    def test_newer_local_work_can_report_a_merge_without_becoming_removable(self):
        w=T.Worktree(repo='repo',path='/tmp/tree',branch='feature',primary=False,base='main',base_source='pr',ahead=1,unpushed=1)
        ref={'number':7,'head_oid':'landed','url':'https://github.com/example/repo/pull/7'}
        with patch.object(T,'git',side_effect=[(0,'new-head',''),(0,'','')]):
            activity=T.merged_activity(w,ref,'gitdir')
        self.assertEqual(activity.state,'MERGED');self.assertIsNone(w.pr);self.assertFalse(w.landed)
        self.assertNotEqual(T.derive_status(w,14),T.MERGED)
        with patch.object(T,'git',side_effect=[(0,'unrelated-head',''),(1,'','')]):
            self.assertIsNone(T.merged_activity(w,ref,'gitdir'))
