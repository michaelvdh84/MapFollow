package com.baseflow.geolocator.location;

import static org.junit.Assert.*;
import static org.mockito.Mockito.*;

import android.location.Location;
import android.os.Bundle;
import com.google.android.gms.location.LocationRequest;
import com.google.android.gms.location.LocationResult;
import com.google.android.gms.location.Priority;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.Test;

public class FusedLocationClientTest {
  private LocationOptions options(int interval, int distance) {
    Map<String, Object> values = new HashMap<>();
    values.put("accuracy", 5);
    values.put("timeInterval", interval);
    values.put("distanceFilter", distance);
    return LocationOptions.parseArguments(values);
  }

  @Test public void requestRetainsCustomIntervalAndRequiresFreshUnbatchedFixes() {
    for (int interval : new int[] {250, 500, 1000, 10000}) {
      LocationRequest request = FusedLocationClient.buildLocationRequest(options(interval, 0));
      assertEquals(Priority.PRIORITY_HIGH_ACCURACY, request.getPriority());
      assertEquals(interval, request.getIntervalMillis());
      assertEquals(interval, request.getMinUpdateIntervalMillis());
      assertEquals(0, request.getMaxUpdateAgeMillis());
      // GMS normalizes zero to at least the interval. Batching needs >= 2x.
      assertFalse(request.isBatched());
      assertEquals(interval, request.getMaxUpdateDelayMillis());
      assertEquals(0f, request.getMinUpdateDistanceMeters(), 0f);
      assertTrue(request.isWaitForAccurateLocation());
    }
  }

  @Test public void profilesRetainDisplacementThresholds() {
    assertEquals(3f, FusedLocationClient.buildLocationRequest(options(2000, 3)).getMinUpdateDistanceMeters(), 0f);
    assertEquals(5f, FusedLocationClient.buildLocationRequest(options(5000, 5)).getMinUpdateDistanceMeters(), 0f);
  }

  @Test public void callbackDeliversEveryFixInOriginalOrder() {
    Location first = mock(Location.class);
    Location second = mock(Location.class);
    Location third = mock(Location.class);
    for (Location location : Arrays.asList(first, second, third)) {
      when(location.getExtras()).thenReturn(mock(Bundle.class));
    }
    LocationResult batch = mock(LocationResult.class);
    when(batch.getLocations()).thenReturn(Arrays.asList(first, second, third));
    NmeaClient nmea = mock(NmeaClient.class);
    List<Location> delivered = new ArrayList<>();
    FusedLocationClient.deliverLocations(batch, options(500, 0), nmea, delivered::add);
    assertEquals(Arrays.asList(first, second, third), delivered);
    verify(nmea).enrichExtrasWithNmea(first);
    verify(nmea).enrichExtrasWithNmea(second);
    verify(nmea).enrichExtrasWithNmea(third);
  }

  @Test public void emptyCallbackDoesNotInventFixes() {
    LocationResult batch = mock(LocationResult.class);
    when(batch.getLocations()).thenReturn(new ArrayList<>());
    PositionChangedCallback callback = mock(PositionChangedCallback.class);
    FusedLocationClient.deliverLocations(batch, null, mock(NmeaClient.class), callback);
    verifyNoInteractions(callback);
  }
}
