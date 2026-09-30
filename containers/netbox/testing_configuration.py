###################################################################
#  NetBox configuration for ci-plugin-tests.sh. Testing only.     #
#  Mounted into the container for the run; it is not in the image. #
###################################################################
#
# The two plugins that have a suite each ship a testing configuration of their
# own, the same but for the plugin's name. This is that file, with the hosts
# and the one plugin under test taken from the environment.

from os import environ

ALLOWED_HOSTS = ['*']

DATABASES = {
    'default': {
        'NAME': 'netbox',
        'USER': 'netbox',
        'PASSWORD': 'netbox',
        'HOST': environ['DB_HOST'],
        'PORT': '',
        'CONN_MAX_AGE': 300,
    }
}

# One plugin, alone. How the plugins behave together is not this run's job.
PLUGINS = [
    environ['PLUGIN_UNDER_TEST'],
]

REDIS = {
    'tasks': {
        'HOST': environ['REDIS_HOST'],
        'PORT': 6379,
        'USERNAME': '',
        'PASSWORD': '',
        'DATABASE': 0,
        'SSL': False,
    },
    'caching': {
        'HOST': environ['REDIS_HOST'],
        'PORT': 6379,
        'USERNAME': '',
        'PASSWORD': '',
        'DATABASE': 1,
        'SSL': False,
    },
}

SECRET_KEY = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

API_TOKEN_PEPPERS = {
    1: 'TEST-VALUE-DO-NOT-USE-TEST-VALUE-DO-NOT-USE-TEST-VALUE-DO-NOT-USE',
}


def __getattr__(name):
    """
    Build SkippingRunner the first time `manage.py test --testrunner` asks for it.

    It cannot be a plain class up here: NetBox imports this module while it is
    still working out its settings, and django.test wants those settings.
    Every other missing name stays missing, which is what NetBox's getattr()
    calls with a default rely on.
    """
    if name != 'SkippingRunner':
        raise AttributeError(name)

    import unittest

    from django.test.runner import DiscoverRunner
    from django.test.utils import iter_test_cases

    # SKIP_TESTS: one "<test id>|<reason>" per line, written by ci-plugin-tests.sh.
    skips = {}
    for line in environ.get('SKIP_TESTS', '').splitlines():
        if line.strip():
            test_id, _, reason = line.partition('|')
            skips[test_id.strip()] = reason.strip()

    class SkippingRunner(DiscoverRunner):
        """Skips the tests the script names, and ends the log with what ran."""

        def build_suite(self, *args, **kwargs):
            suite = super().build_suite(*args, **kwargs)
            unused = dict(skips)
            for test in iter_test_cases(suite):
                reason = unused.pop(test.id(), None)
                if reason is not None:
                    method = getattr(test, test._testMethodName)
                    setattr(test, test._testMethodName, unittest.skip(reason)(method))
            # A skip that matches nothing is a skip nobody can approve: the
            # test was renamed or removed, and the entry has to go with it.
            if unused:
                raise RuntimeError('SKIP_TESTS names no test: ' + ', '.join(sorted(unused)))
            return suite

        def suite_result(self, suite, result, **kwargs):
            print(
                f'ci: ran={result.testsRun} skipped={len(result.skipped)} '
                f'failures={len(result.failures)} errors={len(result.errors)} '
                f'unexpected_successes={len(result.unexpectedSuccesses)}',
                flush=True,
            )
            for test, reason in result.skipped:
                print(f'ci: skipped {test.id()}: {reason}', flush=True)
            for test, _ in result.failures:
                print(f'ci: failed {test.id()}', flush=True)
            for test, _ in result.errors:
                print(f'ci: error {test.id()}', flush=True)
            return super().suite_result(suite, result, **kwargs)

    globals()[name] = SkippingRunner
    return SkippingRunner
