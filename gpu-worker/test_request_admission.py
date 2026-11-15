"""CPU-only regressions for shared admission across catalogue and uploaded-photo jobs."""
import json
import threading
import unittest
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import ThreadingHTTPServer
from unittest import mock

import gpu_worker


class RequestAdmissionTests(unittest.TestCase):
    def setUp(self):
        class Handler(gpu_worker.WorkerHandler):
            mode = 'gpu'
            expected_token = 'test-token'
            def log_message(self, *args):
                pass
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.base = f'http://127.0.0.1:{self.server.server_address[1]}'
        self.catalogue = {'dish_id': 'chicken_rice', 'change_ids': ['brown_rice']}
        self.photo = {'change_id': 'brown_rice', 'image_png_base64': 'fixture', 'mask_png_base64': 'fixture'}

    def post(self, route, body, token='test-token'):
        request = urllib.request.Request(self.base + route, data=json.dumps(body).encode(),
            headers={'Authorization': 'Bearer ' + token}, method='POST')
        try:
            response = urllib.request.urlopen(request, timeout=5)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            return response.status, json.loads(response.read())

    def test_both_routes_share_admission_and_health_remains_responsive(self):
        for first, second, first_body, second_body, worker in [
            ('/v1/generate', '/v1/generate-photo', self.catalogue, self.photo, 'run_gpu_pipeline'),
            ('/v1/generate-photo', '/v1/generate', self.photo, self.catalogue, 'run_photo_pipeline'),
        ]:
            entered, release = threading.Event(), threading.Event()
            def slow(*args, **kwargs):
                entered.set()
                if not release.wait(4):
                    raise AssertionError('test did not release worker')
                return {'test': 'artifact'}
            with self.subTest(first=first), mock.patch.object(gpu_worker, worker, side_effect=slow), \
                 mock.patch.dict(gpu_worker.os.environ, {'WORKER_GPU_CMD': ''}), \
                 mock.patch.object(gpu_worker, 'is_gpu_pipeline_ready', return_value=True), \
                 mock.patch.object(gpu_worker, 'is_photo_pipeline_ready', return_value=True), \
                 ThreadPoolExecutor(max_workers=1) as pool:
                job = pool.submit(self.post, first, first_body)
                try:
                    self.assertTrue(entered.wait(2))
                    self.assertEqual(self.post(second, second_body), (429, {'error': 'gpu_busy'}))
                    self.assertEqual(self.post(second, second_body, token='wrong')[0], 401)
                    with urllib.request.urlopen(self.base + '/healthz', timeout=2) as health:
                        self.assertEqual(health.status, 200)
                finally:
                    release.set()
                self.assertEqual(job.result()[0], 200)
                self.assertEqual(self.post(first, first_body)[0], 200)

    def test_failure_releases_admission_for_both_routes(self):
        for route, body, worker in [('/v1/generate', self.catalogue, 'run_gpu_pipeline'),
                                    ('/v1/generate-photo', self.photo, 'run_photo_pipeline')]:
            with self.subTest(route=route), mock.patch.dict(gpu_worker.os.environ, {'WORKER_GPU_CMD': ''}), \
                 mock.patch.object(gpu_worker, worker, side_effect=[
                     gpu_worker.GpuPipelineUnreadyError('test failure'), {'test': 'artifact'}]):
                self.assertEqual(self.post(route, body)[0], 503)
                self.assertEqual(self.post(route, body)[0], 200)

    def test_malformed_catalogue_values_return_400_and_release_admission(self):
        malformed = [[], None, 'text', {'dish_id': []},
                     {**self.catalogue, 'change_ids': [{}]},
                     {**self.catalogue, 'texture': []}, {**self.catalogue, 'flavour': {}}]
        with mock.patch.object(gpu_worker, 'run_gpu_pipeline', return_value={'test': 'artifact'}) as run:
            for body in malformed:
                self.assertEqual(self.post('/v1/generate', body)[0], 400)
            run.assert_not_called()
            self.assertEqual(self.post('/v1/generate', self.catalogue)[0], 200)


if __name__ == '__main__':
    unittest.main()
