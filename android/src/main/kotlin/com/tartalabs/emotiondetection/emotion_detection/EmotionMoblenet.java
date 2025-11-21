package com.tartalabs.emotiondetection.emotion_detection;

import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.ColorMatrix;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.Paint;
import android.os.Environment;
import android.os.SystemClock;
import android.util.Log;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.HashMap;
import java.util.Map;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import android.content.Context;
import androidx.annotation.NonNull;
import android.graphics.Rect;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.ColorMatrixColorFilter;
import android.graphics.ColorMatrix;
import android.os.SystemClock;
import android.util.Log;
//import com.google_mlkit_commons.InputImageConverter;
import com.google.mlkit.vision.common.InputImage;
import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.gpu.GpuDelegate;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.FloatBuffer;
import android.content.res.AssetFileDescriptor;
import android.content.res.AssetManager;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import org.tensorflow.lite.support.image.TensorImage;
import org.tensorflow.lite.Interpreter.Options;
import org.tensorflow.lite.gpu.CompatibilityList;
import org.tensorflow.lite.DataType;
import org.tensorflow.lite.support.tensorbuffer.TensorBuffer;
import org.tensorflow.lite.support.image.ops.TransformToGrayscaleOp;
import org.tensorflow.lite.support.image.ops.ResizeOp;
import org.tensorflow.lite.support.common.ops.NormalizeOp;
import org.tensorflow.lite.support.image.ImageProcessor;
import java.io.FileOutputStream;
import android.os.Environment;

public class EmotionMoblenet {
    public static String TAG = "EmotionMobilenetV1";
    private final Context context;
    private Interpreter interpreter;
    long modelFileLength;
    boolean initialized = false;
    int saveCount = 20;
    float rBias = 103.939f, gBias = 116.779f, bBias = 123.68f;
    // swapped sandness with neutral as a test
    //final String[] emotions = {"Anger", "Disgust", "Fear", "Happiness", "Sadness","Neutral", "Surprise"};
    final String[] emotions = {"Anger", "Disgust", "Fear", "Happiness", "Neutral", "Sadness", "Surprise"};

    public EmotionMoblenet(Context context, MappedByteBuffer modelBytes) {
        this.context = context; // getApplicationContext(); //context;

        try {
            /*final ByteBuffer model = loadModelFile();
            if(model == null) {
                Log.e(TAG, "Model fole loading error");
            }*/
            modelFileLength = modelBytes.capacity();
            Interpreter.Options options = new Interpreter.Options();
            CompatibilityList compatList = new CompatibilityList();

            if(compatList.isDelegateSupportedOnThisDevice()){
                // if the device has a supported GPU, add the GPU delegate
                GpuDelegate.Options delegateOptions = compatList.getBestOptionsForThisDevice();
                GpuDelegate gpuDelegate = new GpuDelegate(delegateOptions);
                options.addDelegate(gpuDelegate);
            } else {
                // if the GPU is not supported, run on 4 threads
                options.setNumThreads(4);
            }
            //GpuDelegate gpuDelegate = new GpuDelegate();
            //options.addDelegate(gpuDelegate);
            interpreter = new Interpreter(modelBytes/*model*//*, options*/);
            initialized = true;
        } catch ( Exception e) {
            Log.e(TAG, "Error: " + e);
        }
    }

    public Map<String, Double> handlePrediction(MethodCall call, final MethodChannel.Result result) {
        double[] coordinates = {0.0, 0.0};
        byte[] faceImagedata = call.argument("faceImageData");
        Log.e(TAG, "init: " + initialized + " model file: " + modelFileLength + " faceImageData length: " + faceImagedata.length );
        Bitmap faceBmpRGB = BitmapFactory.decodeByteArray(faceImagedata, 0, faceImagedata.length); //ImageUtil.createBitmapFromBytearray(faceImagedata, 224, 224);
        saveBitmap(faceBmpRGB, "faceBmpRGB"+saveCount+".jpg");
        //Bitmap faceBmp = toGrayscale(faceBmpRGB);
        //saveBitmap(faceBmp, "faceGrayBmp"+saveCount+".jpg");
        /*TensorImage faceT1 = TensorImage.fromBitmap(faceBmpRGB);
        saveBitmap(faceT1.getBitmap(), "faceT1_"+saveCount+".jpg");
        faceT1 = new ResizeOp(48, 48, ResizeOp.ResizeMethod.BILINEAR).apply(faceT1);
        saveBitmap(faceT1.getBitmap(), "faceT48x48_"+saveCount+".jpg");
        TensorImage faceT = new TransformToGrayscaleOp().apply(faceT1);


        saveBitmap(faceT.getBitmap(), "faceT_"+saveCount+".jpg");
        */
        TensorImage faceTensorImage = new TensorImage(DataType.FLOAT32);
        //faceGrayImage.load(faceBmp);
        faceTensorImage.load(faceBmpRGB);
        saveBitmap(faceTensorImage.getBitmap(), "faceGrayImage"+saveCount+".jpg");
        ImageProcessor imageProcessor = new ImageProcessor.Builder()
                .add(new ResizeOp(224, 224, ResizeOp.ResizeMethod.BILINEAR))
                .add(new NormalizeOp(new float[] {-rBias, -gBias, -bBias}, new float[] {1.0f, 1.0f, 1.0f}))
                .build();
        TensorImage faceImage = imageProcessor.process(faceTensorImage);
        ByteBuffer buffer = faceImage.getBuffer();

        Log.v(TAG, " buffer: buffer: " + buffer.limit());

        //TensorImage faceImage = TensorImage.createFrom(faceT,DataType.FLOAT32);
        saveBitmap(faceImage.getBitmap(), "faceImageTensor_"+saveCount+".jpg");
        //faceImage.load(faceBmp);

        /*Bitmap leftEye = ImageUtil.createBitmapFromBytearray(leftEyeImageData, 224, 224);
        Bitmap rightEye = ImageUtil.createBitmapFromBytearray(rightEyeImageData, 224, 224);

         */
        //FloatBuffer face = FloatBuffer.wrap(faceImagedata);

        /*ByteBuffer face = ByteBuffer.wrap(faceImagedata);
        ByteBuffer leftEye = ByteBuffer.wrap(leftEyeImageData);
        ByteBuffer rightEye = ByteBuffer.wrap(rightEyeImageData);*/
        //float[] output1={0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};
        TensorBuffer output1 = TensorBuffer.createFixedSize(new int[]{1,7}, DataType.FLOAT32);
        Map<String, Object> inputs = new HashMap<>();
        inputs.put("input_1", faceImage.getBuffer());
        Map<String, Object> outputs = new HashMap<>();
        outputs.put("emotion_preds", output1.getBuffer());
        final String[] keys = interpreter.getSignatureKeys();
        final String[] inputNames = interpreter.getSignatureInputs(keys[0]);
        final String[] outputNames = interpreter.getSignatureOutputs(keys[0]);
        int[][] shapes=new int[4][];
        int[][] shapes1=new int[4][];
        for(int i=0;i<1;i++) {
            shapes[i] = interpreter.getInputTensor(i).shape();
        }
        final int[] shape = interpreter.getInputTensor(0).shape();
        for (String str: inputNames
        ) {
            Log.e(TAG, str);

        }
        for (String str: outputNames
        ) {
            Log.e(TAG, str);

        }
        Log.v(TAG, "signature: " + keys[0]);
        Log.e(TAG, "output: " + interpreter.getOutputTensor(0).dataType());
        Log.e(TAG, "input shape: " + shape[0]+"," + shape[1]+","+ shape[2]+","+shape[3] );
        Log.e(TAG, "input: " + interpreter.getInputTensor(0).dataType());
        //Log.e(TAG, "output shape: " + shape1[0]+"," + shape1[1]+","+ shape1[2]+","+shape1[3] );
        long startTime = SystemClock.uptimeMillis();
        interpreter.runSignature(inputs, outputs, keys[0]);
        Log.v(TAG, " Model time: " + (SystemClock.uptimeMillis()-startTime) + " ms");
        //interpreter.run(inputs, outputs);
        float[] output = output1.getFloatArray();
        Map<String, Double> outputMap = new HashMap<>();
        for(int i=0;i<output.length;i++) {
            outputMap.put(emotions[i], (double) output[i]);
            Log.e(TAG, "output[" + i + "]: " + output[i] + " emotion: " + emotions[i]);
        }
        faceBmpRGB.recycle();
        //faceBmp.recycle();
        return outputMap;
    }

    /**
     * Tested with model: centermobilev2
     * @param call
     * @param result
     * @return
     */

    private void closePrediction(MethodCall call) {
    }

    private void manageModel(MethodCall call, final MethodChannel.Result result) {
    }

    private ByteBuffer convertBitmapToByteBuffer(Bitmap bitmap) {
        int modelInputSize = 4*3*224*224;
        int inputImageWidth = 224;
        int inputImageHeight = 224;
        final  float IMAGE_MEAN = 127.5f;
        final  float IMAGE_STD = 127.5f;
        ByteBuffer byteBuffer = ByteBuffer.allocateDirect(modelInputSize);
        byteBuffer.order(ByteOrder.nativeOrder());

        int[] pixels = new int[inputImageWidth * inputImageHeight];
        bitmap.getPixels(pixels, 0, bitmap.getWidth(), 0, 0, bitmap.getWidth(), bitmap.getHeight());
        int pixel = 0;
        for (int i = 0; i< inputImageWidth; i++) {
            for (int j = 0; j< inputImageHeight; j++) {
                final int pixelVal = pixels[pixel++];

                byteBuffer.putFloat(((pixelVal >> 16 & 0xFF) - IMAGE_MEAN) / IMAGE_STD);
                byteBuffer.putFloat(((pixelVal >> 8 & 0xFF) - IMAGE_MEAN) / IMAGE_STD);
                byteBuffer.putFloat(((pixelVal & 0xFF) - IMAGE_MEAN) / IMAGE_STD);

            }
        }
        bitmap.recycle();

        return byteBuffer;
    }

    public Bitmap toGrayscale(Bitmap bmpOriginal)
    {
        int width, height;
        height = bmpOriginal.getHeight();
        width = bmpOriginal.getWidth();

        Bitmap bmpGrayscale = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(bmpGrayscale);
        Paint paint = new Paint();
        ColorMatrix cm = new ColorMatrix();
        cm.setSaturation(0);
        ColorMatrixColorFilter f = new ColorMatrixColorFilter(cm);
        paint.setColorFilter(f);
        c.drawBitmap(bmpOriginal, 0, 0, paint);
        Bitmap.Config config = bmpGrayscale.getConfig();
        Log.v(TAG, "bmpGrayscale: " + bmpGrayscale.getByteCount());
        return bmpGrayscale;
    }

    //
    // Open model file
    //
    private MappedByteBuffer loadModelFile() throws IOException {
        /*AssetManager assetManager = registar.context().getAssets();

        String key = registrar.lookupKeyForAsset("models/mobilenetv2636.tflite");

        AssetFileDescriptor assetFileDescriptor = assetManager.openFd(key);

         */
        String MODEL_ASSETS_PATH = "models/fer_cnn83.tflite";
        AssetManager assetManager = context.getAssets();
        if(assetManager == null) {
            Log.e(TAG, "Asset manager is null");
        }
        AssetFileDescriptor assetFileDescriptor = context.getAssets().openFd(MODEL_ASSETS_PATH) ;
        FileInputStream fileInputStream = new FileInputStream( assetFileDescriptor.getFileDescriptor() ) ;
        FileChannel fileChannel = fileInputStream.getChannel() ;
        long startoffset = assetFileDescriptor.getStartOffset() ;
        long declaredLength = assetFileDescriptor.getDeclaredLength() ;
        Log.e(TAG, "file length: " + declaredLength + " offset: " + startoffset);
        modelFileLength = declaredLength;
        return fileChannel.map( FileChannel.MapMode.READ_ONLY , startoffset , declaredLength ) ;
    }

    public boolean isExternalStorageWritable() {
        String state = Environment.getExternalStorageState();
        return Environment.MEDIA_MOUNTED.equals(state);
    }

    public void saveBitmap(Bitmap bitmap, String filename) {
        if(saveCount<0) return;
        if (isExternalStorageWritable()) {
            File path = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES);
            File file = new File(path, filename);

            try {
                FileOutputStream out = new FileOutputStream(file);
                bitmap.compress(Bitmap.CompressFormat.JPEG, 100, out);
                out.flush();
                out.close();
            } catch (Exception e) {
                e.printStackTrace();
            }
            saveCount--;
            Log.v(TAG, "Image saved to: "+path+"/"+filename);
        } else {
            Log.e(TAG, "--------- No permission ------------");
        }
    }
}
