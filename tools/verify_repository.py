"""Read-only handoff integrity checks; Python 3.9+, no FPGA or USB access."""
from pathlib import Path
from zipfile import ZipFile
import argparse
import hashlib
import html
import json
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
CANDIDATE=ROOT/'engineering/candidates/sc520_cal_final_2026-11-01'
PROJECT=CANDIDATE/'candidate/sc520_shapes'

def sha(path):
    with path.open('rb') as stream:
        digest=hashlib.sha256()
        for chunk in iter(lambda:stream.read(1024*1024),b''): digest.update(chunk)
    return digest.hexdigest()

def load(path): return json.loads(path.read_text(encoding='utf-8-sig'))

def child(root,relative):
    path=(root/relative.replace('\\','/')).resolve()
    if not path.is_relative_to(root.resolve()): raise ValueError('Path escapes repository')
    return path

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json',type=Path,help='Optional path to save a new check report')
    args=parser.parse_args()
    result={'manifest_files':0,'source_snapshot_files':0,'td_project_references':0,
            'build_source_hashes':0,'simulation_input_hashes':0,'historical_simulation_log_hashes':0,
            'errors':[],'hardware_accessed':False,'simulation_rerun':False,'synthesis_rerun':False}
    def verify(path,expected,label):
        if not path.is_file(): result['errors'].append('Missing '+label)
        elif sha(path).lower()!=expected.lower(): result['errors'].append('Hash mismatch '+label)
    manifest=load(ROOT/'MANIFEST_SHA256.json')
    for relative,expected in manifest.items():
        verify(child(ROOT,relative),expected,relative)
        result['manifest_files']+=1
    with ZipFile(ROOT/'工程源码_可选.zip') as source:
        for info in source.infolist():
            if info.is_dir(): continue
            target=child(ROOT,info.filename)
            verify(target,hashlib.sha256(source.read(info)).hexdigest(),'expanded snapshot '+info.filename)
            result['source_snapshot_files']+=1
    # TD emits XML-like project files with native option syntax. Read only its
    # File entries, preserving the frozen .al bytes instead of reserializing XML.
    al=PROJECT/'td_project/camera_to_dsi_display.al'
    refs=re.findall(r'<File\b[^>]*\bPath="([^"]+)"',al.read_text(encoding='utf-8-sig'))
    if not refs: result['errors'].append('No TD project file references found')
    for relative in refs:
        target=(al.parent/html.unescape(relative).replace('\\','/')).resolve()
        if not target.is_relative_to(ROOT): result['errors'].append('External TD reference '+relative)
        elif not target.is_file(): result['errors'].append('Missing TD reference '+relative)
        result['td_project_references']+=1
    build=load(ROOT/'evidence/build_receipt.json')
    for relative,expected in build['source_sha256'].items():
        verify(child(PROJECT,relative),expected,'build source '+relative)
        result['build_source_hashes']+=1
    simulation=load(ROOT/'evidence/simulation_receipt.json')
    for relative,expected in simulation['sha256'].items():
        verify(child(CANDIDATE,relative),expected,'simulation input '+relative)
        result['simulation_input_hashes']+=1
    for suite in simulation['suites']:
        log_name=suite['log']
        matches=list(CANDIDATE.rglob(Path(log_name).name))
        if len(matches)!=1:
            result['errors'].append('Missing/ambiguous historical simulation log '+log_name)
        else:
            verify(matches[0],suite['log_sha256'],'historical simulation log '+log_name)
            result['historical_simulation_log_hashes']+=1
        if not suite['passed']: result['errors'].append('Historical suite not passed '+suite['suite'])
    version=load(ROOT/'VERSION.json')
    for name,key in [('sram/demo.bit','bit_sha256'),('sram/demo.svf','svf_sha256'),('sram/done.svf','done_svf_sha256')]:
        verify(ROOT/name,version[key],name)
    for name,key in [('evidence/final_timing.rpt','timing_sha256'),('evidence/final_area.rpt','area_sha256')]:
        verify(ROOT/name,build[key],name)
    result['candidate']=version['candidate']
    result['bit_sha256']=sha(ROOT/'sram/demo.bit')
    result['historical_simulation_suite_count']=len(simulation['suites'])
    result['historical_sram_done_passed']=load(ROOT/'evidence/source_board_sram_receipt.json')['done_passed']
    result['passed']=not result['errors']
    text=json.dumps(result,ensure_ascii=False,indent=2)
    print(text)
    if args.json:
        args.json.parent.mkdir(parents=True,exist_ok=True)
        args.json.write_text(text+'\n',encoding='utf-8')
    return 0 if result['passed'] else 1

if __name__=='__main__': sys.exit(main())
