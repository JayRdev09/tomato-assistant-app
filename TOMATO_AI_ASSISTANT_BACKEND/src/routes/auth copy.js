const express = require('express');
const router = express.Router();
const supabaseService = require('../services/supabaseService');
const bcrypt = require('bcryptjs');

// User registration/signup
router.post('/signup', async (req, res) => {
  try {
    const { email, password, firstName, lastName, phoneNumber, address } = req.body;
    
    console.log(`👤 User signup attempt: ${email}`);
    console.log('📝 Signup data:', { email, firstName, lastName, phoneNumber, address });
    
    // Validate input
    if (!email || !password || !firstName || !lastName) {
      return res.status(400).json({
        success: false,
        message: 'Email, password, first name, and last name are required'
      });
    }

    if (password.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters long'
      });
    }

    // Sign up user in Supabase Auth
    const { data, error } = await supabaseService.client.auth.signUp({
      email: email,
      password: password,
    });

    if (error) {
      console.error('❌ Supabase auth error:', error);
      throw error;
    }

    const user = data.user;
    
    if (!user) {
      return res.status(400).json({
        success: false,
        message: 'User creation failed - no user returned'
      });
    }

    console.log(`✅ Auth user created: ${user.id}`);

    // Hash password for storage in users_registered table
    const hashedPassword = await bcrypt.hash(password, 10);

    // Create user profile in users_registered table
    const { data: userInfo, error: userError } = await supabaseService.client
      .from('users_registered')
      .insert({
        user_id: user.id,
        first_name: firstName,
        last_name: lastName,
        address: address || null,
        phone_number: phoneNumber || null,
        email: email,
        password: hashedPassword,
        date_registered: new Date().toISOString()
      })
      .select()
      .single();

    if (userError) {
      console.error('❌ User info creation error:', userError);
      // If users_registered insert fails, delete the auth user to maintain consistency
      await supabaseService.client.auth.admin.deleteUser(user.id);
      throw userError;
    }

    console.log(`✅ User info created successfully: ${user.id}`);
    
    res.status(201).json({
      success: true,
      message: 'User created successfully',
      user: {
        id: user.id,
        email: user.email,
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        address: address,
        emailConfirmedAt: user.email_confirmed_at
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Signup failed:', error.message);
    
    let errorMessage = 'Registration failed';
    
    if (error.message.includes('User already registered')) {
      errorMessage = 'Email already exists';
    } else if (error.message.includes('Weak password')) {
      errorMessage = 'Password is too weak';
    } else if (error.message.includes('duplicate key value violates unique constraint')) {
      errorMessage = 'Email already exists in our system';
    } else if (error.message.includes('users_registered')) {
      errorMessage = 'Failed to create user profile';
    }

    res.status(400).json({
      success: false,
      message: errorMessage,
      error: error.message
    });
  }
});

// User login
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;
    
    console.log(`🔐 User login attempt: ${email}`);
    
    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required'
      });
    }

    // Sign in user in Supabase Auth
    const { data, error } = await supabaseService.client.auth.signInWithPassword({
      email: email,
      password: password,
    });

    if (error) {
      console.error('❌ Supabase auth error:', error);
      throw error;
    }

    const user = data.user;
    const session = data.session;

    // Get user info from users_registered table
    const { data: userInfo, error: userError } = await supabaseService.client
      .from('users_registered')
      .select('*')
      .eq('email', email)
      .single();

    if (userError) {
      console.error('❌ User info fetch error:', userError);
      throw userError;
    }

    console.log(`✅ User logged in successfully: ${user.id}`);
    
    res.json({
      success: true,
      message: 'Login successful',
      user: {
        id: user.id,
        email: user.email,
        firstName: userInfo.first_name,
        lastName: userInfo.last_name,
        phoneNumber: userInfo.phone_number,
        address: userInfo.address,
        emailConfirmedAt: user.email_confirmed_at
      },
      session: {
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        expires_at: session.expires_at
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Login failed:', error.message);
    
    let errorMessage = 'Login failed';
    if (error.message.includes('Invalid login credentials')) {
      errorMessage = 'Invalid email or password';
    } else if (error.message.includes('Email not confirmed')) {
      errorMessage = 'Please confirm your email address before logging in';
    }

    res.status(401).json({
      success: false,
      message: errorMessage,
      error: error.message
    });
  }
});

// Verify Supabase access token
router.post('/verify-token', async (req, res) => {
  try {
    const { access_token } = req.body;
    
    if (!access_token) {
      return res.status(400).json({
        success: false,
        message: 'Access token is required'
      });
    }

    console.log('🔍 Verifying Supabase access token...');
    
    // Get user from session using the token
    const { data, error } = await supabaseService.client.auth.getUser(access_token);
    
    if (error) throw error;

    const user = data.user;
    
    // Get user info from users_registered table
    const { data: userInfo, error: userError } = await supabaseService.client
      .from('users_registered')
      .select('*')
      .eq('user_id', user.id)
      .single();

    if (userError && userError.code !== 'PGRST116') {
      throw userError;
    }

    console.log(`✅ Token verified for user: ${user.id}`);
    
    res.json({
      success: true,
      message: 'Token verified successfully',
      user: {
        id: user.id,
        email: user.email,
        firstName: userInfo?.first_name || '',
        lastName: userInfo?.last_name || '',
        phoneNumber: userInfo?.phone_number || '',
        address: userInfo?.address || '',
        emailConfirmedAt: user.email_confirmed_at
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Token verification failed:', error.message);
    res.status(401).json({
      success: false,
      message: 'Invalid authentication token',
      error: error.message
    });
  }
});

// Get user profile
router.get('/profile', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Authentication token required'
      });
    }

    const accessToken = authHeader.split('Bearer ')[1];
    
    // Get user from session
    const { data, error } = await supabaseService.client.auth.getUser(accessToken);
    
    if (error) throw error;

    const user = data.user;
    
    // Get user info from users_registered table
    const { data: userInfo, error: userError } = await supabaseService.client
      .from('users_registered')
      .select('*')
      .eq('user_id', user.id)
      .single();

    if (userError) {
      return res.status(404).json({
        success: false,
        message: 'User profile not found'
      });
    }

    res.json({
      success: true,
      user: {
        id: user.id,
        email: userInfo.email,
        firstName: userInfo.first_name,
        lastName: userInfo.last_name,
        phoneNumber: userInfo.phone_number,
        address: userInfo.address,
        dateRegistered: userInfo.date_registered
      }
    });

  } catch (error) {
    console.error('❌ Profile fetch failed:', error.message);
    res.status(401).json({
      success: false,
      message: 'Authentication failed'
    });
  }
});

// Update user profile
router.put('/profile', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Authentication token required'
      });
    }

    const accessToken = authHeader.split('Bearer ')[1];
    const { firstName, lastName, phoneNumber, address } = req.body;

    // Get user from session
    const { data, error } = await supabaseService.client.auth.getUser(accessToken);
    
    if (error) throw error;

    const user = data.user;

    const updateData = {};
    
    if (firstName !== undefined) updateData.first_name = firstName;
    if (lastName !== undefined) updateData.last_name = lastName;
    if (phoneNumber !== undefined) updateData.phone_number = phoneNumber;
    if (address !== undefined) updateData.address = address;

    // Update user info in users_registered table
    const { data: updatedUser, error: updateError } = await supabaseService.client
      .from('users_registered')
      .update(updateData)
      .eq('user_id', user.id)
      .select()
      .single();

    if (updateError) throw updateError;

    res.json({
      success: true,
      message: 'Profile updated successfully',
      user: {
        id: user.id,
        firstName: updatedUser.first_name,
        lastName: updatedUser.last_name,
        phoneNumber: updatedUser.phone_number,
        address: updatedUser.address
      }
    });

  } catch (error) {
    console.error('❌ Profile update failed:', error.message);
    res.status(400).json({
      success: false,
      message: 'Profile update failed: ' + error.message
    });
  }
});

// Delete user account - UPDATED to use users_registered
router.delete('/account', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        message: 'Authentication token required'
      });
    }

    const accessToken = authHeader.split('Bearer ')[1];
    
    // Get user from session
    const { data, error } = await supabaseService.client.auth.getUser(accessToken);
    
    if (error) throw error;

    const user = data.user;

    // Delete user profile from users_registered table
    const { error: profileError } = await supabaseService.client
      .from('users_registered')
      .delete()
      .eq('user_id', user.id);

    if (profileError) throw profileError;

    // Delete user from Auth
    const { error: authError } = await supabaseService.client.auth.admin.deleteUser(user.id);
    
    if (authError) throw authError;

    console.log(`🗑️ User account deleted: ${user.id}`);
    
    res.json({
      success: true,
      message: 'Account deleted successfully'
    });

  } catch (error) {
    console.error('❌ Account deletion failed:', error.message);
    res.status(400).json({
      success: false,
      message: 'Account deletion failed: ' + error.message
    });
  }
});

module.exports = router;