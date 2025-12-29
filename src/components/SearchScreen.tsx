import { MapPin, Clock, ChevronLeft, Search, SlidersHorizontal } from 'lucide-react';
import { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { ImageWithFallback } from './figma/ImageWithFallback';

interface SpotResult {
  id: string;
  name: string;
  address: string;
  icon?: string;
  status?: string;
  type?: 'recent' | 'saved';
}

interface UserResult {
  id: string;
  name: string;
  username: string;
  avatar: string;
  isFollowing: boolean;
  mutualFriends?: number;
}

interface SearchScreenProps {
  onClose: () => void;
  onSelectSpot: (spotName: string) => void;
  onFiltersClick?: () => void;
  recentSpots?: SpotResult[];
  recentUsers?: UserResult[];
  searchResults?: {
    spots?: SpotResult[];
    users?: UserResult[];
  };
  onSearch?: (query: string, mode: 'spots' | 'users') => void;
  onUserFollow?: (userId: string, isFollowing: boolean) => void;
  initialSearchMode?: 'spots' | 'users';
}

export function SearchScreen({
  onClose,
  onSelectSpot,
  onFiltersClick,
  recentSpots = [],
  recentUsers = [],
  searchResults = {},
  onSearch,
  onUserFollow,
  initialSearchMode = 'spots',
}: SearchScreenProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [searchMode, setSearchMode] = useState<'spots' | 'users'>(initialSearchMode);
  const [followStates, setFollowStates] = useState<Record<string, boolean>>({});

  // Debounce search query
  useEffect(() => {
    if (onSearch && searchQuery.trim()) {
      const timeoutId = setTimeout(() => {
        onSearch(searchQuery, searchMode);
      }, 300);

      return () => clearTimeout(timeoutId);
    }
  }, [searchQuery, searchMode, onSearch]);

  const handleSelectResult = (result: SpotResult) => {
    onSelectSpot(result.name);
    onClose();
  };

  const handleFollowToggle = (userId: string, currentState: boolean) => {
    const newState = !currentState;
    setFollowStates(prev => ({
      ...prev,
      [userId]: newState,
    }));

    if (onUserFollow) {
      onUserFollow(userId, newState);
    }
  };

  const isUserFollowing = (userId: string, defaultState: boolean) => {
    return followStates[userId] !== undefined ? followStates[userId] : defaultState;
  };

  const renderTabs = () => (
    <div className="flex w-full border-b border-gray-200">
      <button
        onClick={() => setSearchMode('spots')}
        className="flex-1 py-3 text-center relative"
        aria-label="Spots tab"
      >
        <span
          className={`text-sm ${
            searchMode === 'spots' ? 'text-gray-900 font-medium' : 'text-gray-400'
          }`}
        >
          Spots
        </span>
        {searchMode === 'spots' && (
          <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-gray-900" />
        )}
      </button>
      <button
        onClick={() => setSearchMode('users')}
        className="flex-1 py-3 text-center relative"
        aria-label="Users tab"
      >
        <span
          className={`text-sm ${
            searchMode === 'users' ? 'text-gray-900 font-medium' : 'text-gray-400'
          }`}
        >
          Users
        </span>
        {searchMode === 'users' && (
          <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-gray-900" />
        )}
      </button>
    </div>
  );

  const renderUserItem = (user: UserResult) => {
    const following = isUserFollowing(user.id, user.isFollowing);
    return (
      <div
        key={user.id}
        className="flex items-center justify-between py-3 border-b border-gray-50 last:border-0"
      >
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <div className="w-12 h-12 rounded-full overflow-hidden bg-gray-200 flex-shrink-0">
            <ImageWithFallback
              src={user.avatar}
              alt={user.name}
              className="w-full h-full object-cover"
            />
          </div>

          <div className="flex-1 min-w-0 text-left">
            <div className="text-sm text-gray-900 truncate font-medium">{user.name}</div>
            <div className="text-xs text-gray-500 truncate">
              {user.username}
              {user.mutualFriends ? ` · ${user.mutualFriends} mutual friends` : ''}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 flex-shrink-0 ml-3">
          <button
            onClick={(e) => {
              e.stopPropagation();
              handleFollowToggle(user.id, following);
            }}
            className={`px-4 py-1.5 rounded-full text-xs transition-colors flex-shrink-0 font-medium min-h-[44px] ${
              following
                ? 'bg-gray-100 text-gray-700 active:bg-gray-200'
                : 'bg-[#5DB0B8] text-white active:bg-[#4a9099]'
            }`}
            aria-label={following ? `Unfollow ${user.name}` : `Follow ${user.name}`}
          >
            {following ? 'Following' : 'Follow'}
          </button>
        </div>
      </div>
    );
  };

  const currentSearchResults = searchMode === 'spots' 
    ? (searchResults.spots || [])
    : (searchResults.users || []);

  return (
    <motion.div
      initial={{ x: '100%' }}
      animate={{ x: 0 }}
      exit={{ x: '100%' }}
      transition={{ type: 'spring', damping: 30, stiffness: 300 }}
      className="absolute inset-0 bg-white z-50 flex flex-col overflow-hidden"
    >
      {/* Search Header */}
      <div className="flex items-center gap-3 px-4 pt-4 pb-3 bg-white border-b border-gray-200">
        <button
          onClick={onClose}
          className="w-11 h-11 flex items-center justify-center flex-shrink-0 active:scale-95 transition-transform min-h-[44px] min-w-[44px]"
          aria-label="Close search"
        >
          <ChevronLeft className="w-6 h-6 text-gray-900" strokeWidth={2} />
        </button>

        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search here"
            autoFocus
            className="w-full pl-10 pr-4 py-2 bg-gray-100 text-gray-900 placeholder:text-gray-400 rounded-lg focus:outline-none focus:ring-2 focus:ring-[#5DB0B8]/30 text-sm min-h-[44px]"
            aria-label="Search input"
          />
        </div>
        {onFiltersClick && (
          <button
            onClick={onFiltersClick}
            className="w-11 h-11 flex items-center justify-center flex-shrink-0 active:scale-95 transition-transform min-h-[44px] min-w-[44px]"
            aria-label="Open filters"
          >
            <SlidersHorizontal className="w-5 h-5 text-gray-900" strokeWidth={2} />
          </button>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto bg-white scrollbar-hide">
        {!searchQuery ? (
          <>
            {/* Tab Bar */}
            {renderTabs()}
            {searchMode === 'spots' ? (
              <>
                {/* Recent Spots Section */}
                <div className="px-2.5 pt-2">
                  <div className="flex items-center justify-between mb-2 px-1.5">
                    <h3 className="text-gray-900 text-[15px] font-medium">Recent</h3>
                  </div>
                  <div className="space-y-0">
                    {recentSpots.length > 0 ? (
                      recentSpots.map((item) => (
                        <button
                          key={item.id}
                          onClick={() => handleSelectResult(item)}
                          className="w-full flex items-start gap-3 px-2 py-2.5 rounded-lg active:bg-gray-100 transition-colors min-h-[44px]"
                        >
                          <div className="w-10 h-10 flex items-center justify-center flex-shrink-0">
                            {item.icon ? (
                              <div className="w-10 h-10 rounded-full bg-gradient-to-br from-pink-100 to-purple-100 flex items-center justify-center text-lg">
                                {item.icon}
                              </div>
                            ) : (
                              <div className="w-10 h-10 rounded-full bg-gray-100 flex items-center justify-center">
                                <Clock className="w-[18px] h-[18px] text-gray-500" />
                              </div>
                            )}
                          </div>

                          <div className="flex-1 text-left min-w-0 pt-0.5">
                            <div className="text-gray-900 text-[15px] leading-tight font-medium">{item.name}</div>
                            {item.address && (
                              <div className="text-gray-500 text-[13px] mt-0.5 leading-tight">{item.address}</div>
                            )}
                            {item.status && (
                              <div className="text-gray-500 text-[13px] mt-0.5 leading-tight">{item.status}</div>
                            )}
                          </div>
                        </button>
                      ))
                    ) : (
                      <div className="text-center py-12">
                        <div className="text-gray-500 text-sm">No recent searches</div>
                      </div>
                    )}
                  </div>
                </div>
              </>
            ) : searchMode === 'users' ? (
              <>
                {/* Recent Users Section */}
                <div className="px-4 pt-4">
                  <div className="flex items-center justify-between mb-2">
                    <h3 className="text-gray-900 text-[15px] font-medium">Recent</h3>
                  </div>
                  <div className="space-y-1">
                    {recentUsers.length > 0 ? (
                      recentUsers.map(renderUserItem)
                    ) : (
                      <div className="text-center py-12">
                        <div className="text-gray-500 text-sm">No recent users</div>
                      </div>
                    )}
                  </div>
                </div>
              </>
            ) : null}
          </>
        ) : (
          /* Search Results */
          <>
            {/* Tab Bar */}
            {renderTabs()}
            {searchMode === 'spots' ? (
              <div className="px-2.5 pt-2">
                <div className="space-y-0">
                  {currentSearchResults.length > 0 ? (
                    (currentSearchResults as SpotResult[]).map((result) => (
                      <button
                        key={result.id}
                        onClick={() => handleSelectResult(result)}
                        className="w-full flex items-start gap-3 px-2 py-2.5 rounded-lg active:bg-gray-100 transition-colors min-h-[44px]"
                      >
                        <div className="w-10 h-10 flex items-center justify-center flex-shrink-0">
                          <div className="w-10 h-10 rounded-full bg-red-100 flex items-center justify-center">
                            <MapPin className="w-[18px] h-[18px] text-red-500" fill="currentColor" />
                          </div>
                        </div>

                        <div className="flex-1 text-left min-w-0 pt-0.5">
                          <div className="text-gray-900 text-[15px] leading-tight font-medium">{result.name}</div>
                          <div className="text-gray-500 text-[13px] mt-0.5 leading-tight">{result.address}</div>
                          {result.status && (
                            <div className="text-gray-500 text-[13px] mt-0.5 leading-tight">{result.status}</div>
                          )}
                        </div>
                      </button>
                    ))
                  ) : (
                    <div className="text-center py-12">
                      <div className="text-gray-500 text-sm">No spots found</div>
                    </div>
                  )}
                </div>
              </div>
            ) : searchMode === 'users' ? (
              <div className="px-4 pt-2">
                <div className="space-y-1">
                  {currentSearchResults.length > 0 ? (
                    (currentSearchResults as UserResult[]).map(renderUserItem)
                  ) : (
                    <div className="text-center py-12">
                      <div className="text-gray-500 text-sm">No users found</div>
                    </div>
                  )}
                </div>
              </div>
            ) : null}
          </>
        )}
      </div>
    </motion.div>
  );
}

