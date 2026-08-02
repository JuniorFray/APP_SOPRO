# sherpa-onnx: o libsherpa-onnx-jni.so acessa estas classes, campos e metodos
# via JNI por nome FIXO (GetFieldID/FindClass). R8 nao enxerga esse uso e
# ofusca campos/classes (ex: campo "model" -> "a"), quebrando o binding nativo
# com "fid == null" / ClassNotFoundException / SIGABRT no release.
# Preservar tudo em com.k2fsa.** resolve o crash.
-keep class com.k2fsa.** { *; }
-keepclassmembers class com.k2fsa.** { *; }
