#import "PythonRuntime.h"
#import <Python/Python.h>
#import <JavaScriptCore/JavaScriptCore.h>
#include <stdatomic.h>
#include <stdbool.h>

static atomic_bool operationCancelled = false;
static void (^progressHandler)(NSString *);

static PyObject *bridge_emit(PyObject *self, PyObject *args) {
    const char *json;
    if (!PyArg_ParseTuple(args, "s", &json)) return NULL;
    if (progressHandler) progressHandler([NSString stringWithUTF8String:json]);
    Py_RETURN_NONE;
}

static PyObject *bridge_is_cancelled(PyObject *self, PyObject *args) {
    return PyBool_FromLong(atomic_load(&operationCancelled));
}

static PyObject *bridge_evaluate_js(PyObject *self, PyObject *args) {
    const char *script;
    if (!PyArg_ParseTuple(args, "s", &script)) return NULL;
    @autoreleasepool {
        JSContext *context = [[JSContext alloc] init];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        __block NSString *failure = nil;
        context.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
            failure = [exception toString];
        };
        context[@"_nativePrint"] = ^(NSString *value) { [lines addObject:value ?: @""]; };
        [context evaluateScript:@"globalThis.console = { log: (...args) => _nativePrint(args.join(' ')), warn: () => {}, error: () => {} }; globalThis.print = (...args) => console.log(...args);"];
        [context evaluateScript:[NSString stringWithUTF8String:script]];
        if (failure || lines.count == 0) {
            PyErr_SetString(PyExc_RuntimeError, (failure ?: @"JavaScriptCore 결과가 없습니다.").UTF8String);
            return NULL;
        }
        // EJS writes one JSON result via console.log.
        return PyUnicode_FromString(lines.lastObject.UTF8String);
    }
}

static PyMethodDef bridge_methods[] = {
    {"emit", bridge_emit, METH_VARARGS, NULL},
    {"is_cancelled", bridge_is_cancelled, METH_NOARGS, NULL},
    {"evaluate_js", bridge_evaluate_js, METH_VARARGS, NULL},
    {NULL, NULL, 0, NULL}
};
static struct PyModuleDef bridge_module = {
    PyModuleDef_HEAD_INIT, "_ios_bridge", NULL, -1, bridge_methods
};
PyMODINIT_FUNC PyInit__ios_bridge(void) { return PyModule_Create(&bridge_module); }

static NSString *errorJSON(NSString *message) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"ok": @NO, @"error": message ?: @"Python 엔진 오류"}
                                                 options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@implementation PythonRuntime

+ (void)prepareOperation { atomic_store(&operationCancelled, false); }
+ (void)cancel { atomic_store(&operationCancelled, true); }

+ (NSString *)initializePython {
    if (Py_IsInitialized()) return nil;
    if (PyImport_AppendInittab("_ios_bridge", PyInit__ios_bridge) == -1)
        return @"네이티브 모듈을 등록할 수 없습니다.";
    NSString *resource = NSBundle.mainBundle.resourcePath;
    NSString *home = [resource stringByAppendingPathComponent:@"python"];
    NSString *app = [resource stringByAppendingPathComponent:@"app"];
    NSString *stdlib = [home stringByAppendingPathComponent:@"lib/python3.13"];
    NSString *dynload = [stdlib stringByAppendingPathComponent:@"lib-dynload"];
    NSMutableArray<NSString *> *pythonPaths = [NSMutableArray array];
    NSArray<NSURL *> *supportURLs = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                                          inDomains:NSUserDomainMask];
    NSURL *engineRoot = [[supportURLs firstObject] URLByAppendingPathComponent:@"YTDLPEngine" isDirectory:YES];
    NSString *marker = [NSString stringWithContentsOfURL:[engineRoot URLByAppendingPathComponent:@"current"]
                                                encoding:NSUTF8StringEncoding error:nil];
    marker = [marker stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSCharacterSet *invalidVersion = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789."] invertedSet];
    if (marker.length > 0 && [marker rangeOfCharacterFromSet:invalidVersion].location == NSNotFound) {
        NSURL *candidate = [engineRoot URLByAppendingPathComponent:marker isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:[[candidate URLByAppendingPathComponent:@"yt_dlp/__init__.py"] path]]) {
            [pythonPaths addObject:candidate.path];
        }
    }
    [pythonPaths addObjectsFromArray:@[stdlib, dynload, app]];
    NSString *paths = [pythonPaths componentsJoinedByString:@":"];
    setenv("PYTHONHOME", home.UTF8String, 1);
    setenv("PYTHONPATH", paths.UTF8String, 1);
    setenv("YTDLP_BUNDLED_APP_PATH", app.UTF8String, 1);
    setenv("YTDLP_UPDATE_ROOT", engineRoot.path.UTF8String, 1);
    setenv("SSL_CERT_FILE", [[app stringByAppendingPathComponent:@"certifi/cacert.pem"] UTF8String], 1);

    PyPreConfig pre;
    PyPreConfig_InitPythonConfig(&pre);
    pre.utf8_mode = 1;
    PyStatus status = Py_PreInitialize(&pre);
    if (PyStatus_Exception(status)) return @"Python 사전 초기화에 실패했습니다.";

    PyConfig config;
    PyConfig_InitPythonConfig(&config);
    config.buffered_stdio = 0;
    config.write_bytecode = 0;
    config.install_signal_handlers = 0;
    status = Py_InitializeFromConfig(&config);
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status))
        return [NSString stringWithUTF8String:status.err_msg ?: "Python initialization failed"];
    // Release the initialization thread's GIL; later calls may use another GCD worker.
    PyEval_SaveThread();
    return nil;
}

+ (NSString *)runRequest:(NSString *)request progress:(void (^)(NSString *))progress {
    @autoreleasepool {
        // Swift dispatches every call on one serial queue.
        NSString *failure = [self initializePython];
        if (failure) return errorJSON(failure);
        PyGILState_STATE gil = PyGILState_Ensure();
        progressHandler = [progress copy];
        PyObject *module = PyImport_ImportModule("downloader");
        PyObject *function = module ? PyObject_GetAttrString(module, "run") : NULL;
        PyObject *argument = PyUnicode_FromString(request.UTF8String);
        PyObject *result = function ? PyObject_CallFunctionObjArgs(function, argument, NULL) : NULL;
        NSString *json = nil;
        if (result && PyUnicode_Check(result)) {
            const char *value = PyUnicode_AsUTF8(result);
            if (value) json = [NSString stringWithUTF8String:value];
        }
        if (!json) {
            if (PyErr_Occurred()) PyErr_Print();
            json = errorJSON(@"다운로드 엔진을 불러올 수 없습니다. 빌드 로그와 포함된 Python 패키지를 확인해 주세요.");
        }
        Py_XDECREF(result); Py_XDECREF(argument); Py_XDECREF(function); Py_XDECREF(module);
        progressHandler = nil;
        PyGILState_Release(gil);
        return json;
    }
}
@end
